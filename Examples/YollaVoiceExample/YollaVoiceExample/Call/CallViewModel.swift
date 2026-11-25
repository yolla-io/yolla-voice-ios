//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import CallKit
import Foundation
import Observation
import YollaVoiceSDK

/// The subset of `Call` the view model drives; `Call` conforms, tests use a fake.
protocol CallControlling: AnyObject, Sendable {
    var callID: String? { get }
    func setMuted(_ muted: Bool) async
    func setOnHold(_ hold: Bool) async throws
    func sendDigits(_ digits: String) async throws
    func hangup() async
    func stats() async -> CallStats
}

extension Call: CallControlling {}

/// How long the tones last that the SDK plays when a call ends. The app waits for them before it lets the audio go.
nonisolated struct EndToneDurations: Sendable, Equatable {
    /// After a connected call.
    var ended: Duration = .milliseconds(500)
    var busy: Duration = .seconds(3)
    var noAnswer: Duration = .milliseconds(800)
    /// The call failed or was rejected before the answer.
    var failed: Duration = .seconds(2)

    /// The SDK's tones, as its integration guide lists them.
    static let sdk = EndToneDurations()
}

/// One call as seen by the UI. Receives `CallDelegate` callbacks (already on the main actor) and mirrors them into state.
///
/// With CallKit on, user commands (end, mute, hold) are *requested* from CallKit and executed when the matching
/// `CXAction` is performed (`hangupFromCallKit`, `applyMute`, `applyHold`), so the system call UI stays in sync.
@MainActor @Observable
final class CallViewModel: CallDelegate, Identifiable {
    enum Phase: Equatable {
        case connecting
        case ringing(earlyMedia: Bool)
        case connected
        case reconnecting(reason: String)
        case ended(reason: Call.EndReason, error: VoiceError?)

        var isActive: Bool { if case .ended = self { return false } else { return true } }
    }

    let uuid: UUID
    let number: String
    /// When the call was placed.
    let startedAt = Date()
    /// Called once, when the call has ended, with its line for the call history.
    var onEnded: ((CallRecord) -> Void)?
    private(set) var phase: Phase = .connecting
    private(set) var connectedAt: Date?
    private(set) var isMuted = false
    private(set) var isOnHold = false
    private(set) var warnings: Set<CallQualityWarning> = []
    private(set) var stats: CallStats?
    private(set) var callID: String?
    private(set) var lastError: String?
    /// How long the SDK's tone for the end of this call lasts; set when the call ends.
    private(set) var endToneDuration: Duration = .zero

    private var call: (any CallControlling)?
    private var statsTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?
    private var hangupPending = false
    /// Set the moment the SDK reports the end, before `phase` (a failed call learns its reason one step later).
    private var hasEnded = false
    /// The delayed end report to CallKit, when there is one. A new call waits for it: until then CallKit still has
    /// this call, and a call placed with the same token has the same UUID.
    private(set) var endReport: Task<Void, Never>?
    private var endedViaCallKit = false
    private let logs: LogStore
    private let callKit: (any CallKitControlling)?
    private let tones: EndToneDurations

    nonisolated var id: UUID { uuid }

    /// The end of the call waits for the SDK's tone to play; `tones` says how long each one is.
    init(
        uuid: UUID,
        number: String,
        logs: LogStore,
        callKit: (any CallKitControlling)?,
        tones: EndToneDurations = .sdk
    ) {
        self.uuid = uuid; self.number = number; self.logs = logs; self.callKit = callKit; self.tones = tones
    }

    func attach(_ call: any CallControlling) {
        callID = call.callID
        // A call can fail before `connect` returns it: keeping it now would keep it, and this object, for good.
        guard !hasEnded else { return }
        self.call = call
        if hangupPending {
            hangupPending = false
            Task { await call.hangup() }
        }
    }

    // MARK: Commands from the UI

    func toggleMute() async {
        if let callKit {
            do { try await callKit.setMuted(uuid: uuid, !isMuted) } catch { report(error) }
        } else {
            await applyMute(!isMuted)
        }
    }

    func toggleHold() async {
        if let callKit {
            do { try await callKit.setHeld(uuid: uuid, !isOnHold) } catch { report(error) }
        } else {
            do { try await applyHold(!isOnHold) } catch { report(error) }
        }
    }

    func send(digit: String) async {
        guard let call else { return }
        do { try await call.sendDigits(digit); logs.app("dtmf \(digit)") } catch { report(error) }
    }

    func hangup() async {
        if let callKit {
            do { try await callKit.endCall(uuid: uuid) } catch {
                report(error); await hangupFromCallKit(viaCallKit: false) // refused: end it anyway, and report the end
            }
        } else {
            await hangupFromCallKit()
        }
    }

    // MARK: Commands performed by CallKit actions (or directly without CallKit)

    func applyMute(_ muted: Bool) async {
        guard let call else { return }
        isMuted = muted
        await call.setMuted(muted)
        logs.app("mute \(muted)")
    }

    func applyHold(_ hold: Bool) async throws {
        guard let call else { throw VoiceError.invalidCallState }
        do {
            try await call.setOnHold(hold)
            isOnHold = hold
            logs.app("hold \(hold)")
        } catch { report(error); throw error }
    }

    /// Ends the call now, or as soon as `connect` returns when the end request arrived during setup.
    func hangupFromCallKit(viaCallKit: Bool = true) async {
        endedViaCallKit = viaCallKit && callKit != nil
        guard let call else { hangupPending = true; logs.app("hangup requested before connect finished"); return }
        logs.app("hangup")
        await call.hangup()
    }

    private func report(_ error: Error) {
        let text = (error as? VoiceError).map { "\($0.code): \($0.message)" } ?? error.localizedDescription
        lastError = text
        logs.app("error \(text)")
        errorTask?.cancel()
        errorTask = Task {
            try? await Task.sleep(for: .seconds(4)); lastError = nil
        }
    }

    // MARK: CallDelegate

    func callDidStartRinging(
        _ call: Call,
        earlyMedia: Bool
    ) {
        phase = .ringing(earlyMedia: earlyMedia)
        logs.app("ringing (early media: \(earlyMedia))")
    }

    func callDidConnect(_ call: Call) {
        didConnect()
        callID = call.callID
        startStats(call)
    }

    /// Shared connect path (also used by tests, which cannot construct a `Call`).
    func didConnect() {
        phase = .connected
        connectedAt = Date()
        logs.app("connected")
        callKit?.reportConnected(uuid)
    }

    func callIsReconnecting(
        _ call: Call,
        error: VoiceError
    ) {
        phase = .reconnecting(reason: error.code)
        logs.app("reconnecting: \(error.code)")
    }

    func callDidReconnect(_ call: Call) {
        phase = .connected
        logs.app("reconnected")
    }

    func callDidFailToConnect(
        _ call: Call,
        error: VoiceError
    ) {
        hasEnded = true
        // The delegate method carries no reason; the call knows whether it was busy, unanswered or rejected.
        Task { callDidFailToConnect(reason: await call.endReason, error: error) }
    }

    /// Shared failure path (also used by tests, which cannot construct a `Call`).
    func callDidFailToConnect(
        reason: Call.EndReason?,
        error: VoiceError
    ) {
        callDidDisconnect(reason: reason ?? .failed, error: error)
    }

    func callDidDisconnect(
        _ call: Call,
        reason: Call.EndReason,
        error: VoiceError?
    ) {
        callDidDisconnect(reason: reason, error: error)
    }

    /// How long the SDK's tone for the end of a call lasts, with a small margin; zero when the SDK plays none. The
    /// CallKit end report and the release of the audio session wait for it: either one sooner cuts the tone.
    nonisolated static func endToneDuration(
        reason: Call.EndReason,
        wasConnected: Bool,
        tones: EndToneDurations
    ) -> Duration {
        let tone: Duration
        if wasConnected {
            tone = tones.ended
        } else {
            switch reason {
            case .busy: tone = tones.busy
            case .noAnswer: tone = tones.noAnswer
            case .failed, .rejected: tone = tones.failed
            case .localHangup, .remoteHangup, .cancelled: return .zero
            @unknown default: return .zero
            }
        }
        return tone + .milliseconds(100)
    }

    /// Shared end path (also used by tests, which cannot construct a `Call`).
    func callDidDisconnect(
        reason: Call.EndReason,
        error: VoiceError?
    ) {
        hasEnded = true
        statsTask?.cancel(); statsTask = nil
        call = nil // a `Call` keeps its delegate (this object): holding the ended call would keep both alive
        phase = .ended(reason: reason, error: error)
        endToneDuration = Self.endToneDuration(reason: reason, wasConnected: connectedAt != nil, tones: tones)
        logs.app("ended: \(Self.describe(reason, error: error))")
        if let onEnded {
            self.onEnded = nil
            onEnded(
                Self.record(
                    number: number,
                    startedAt: startedAt,
                    connectedAt: connectedAt,
                    reason: reason,
                    error: error
                )
            )
        }
        if let cxReason = Self.cxEndedReason(reason, endedViaCallKit: endedViaCallKit) {
            let callKit = self.callKit, uuid = self.uuid, delay = endToneDuration
            endReport = Task { @MainActor in
                try? await Task.sleep(for: delay)
                callKit?.reportEnded(uuid, reason: cxReason)
            }
        }
    }

    func callDidReceiveQualityWarnings(
        _ call: Call,
        current: Set<CallQualityWarning>,
        previous: Set<CallQualityWarning>
    ) {
        warnings = current
        logs.app("quality warnings: \(current.map(\.rawValue).sorted().joined(separator: ","))")
    }

    private func startStats(_ call: any CallControlling) {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.phase.isActive else { return }
                self.stats = await call.stats()
            }
        }
    }

    // MARK: Mapping

    /// The call's line in the history. A call that was answered has a duration, also when it ended with an error.
    nonisolated static func record(
        number: String,
        startedAt: Date,
        connectedAt: Date?,
        endedAt: Date = Date(),
        reason: Call.EndReason,
        error: VoiceError?
    ) -> CallRecord {
        let failed: Bool
        switch reason {
        case .busy, .noAnswer, .rejected, .failed: failed = true
        case .localHangup, .remoteHangup, .cancelled: failed = error != nil
        @unknown default: failed = error != nil
        }
        return CallRecord(
            number: number,
            date: startedAt,
            duration: connectedAt.map { endedAt.timeIntervalSince($0) },
            outcome: describe(reason, error: error),
            failed: failed
        )
    }

    nonisolated static func describe(
        _ reason: Call.EndReason,
        error: VoiceError?
    ) -> String {
        switch reason {
        case .busy: return "Busy"
        case .noAnswer: return "No answer"
        case .rejected: return "Rejected"
        case .remoteHangup: return "Call ended by the other side"
        case .localHangup: return "Call ended"
        case .cancelled: return "Cancelled"
        case .failed:
            guard let error else { return "Failed" }
            let sip = error.sipStatus.map { ", SIP \($0)" } ?? ""
            return "Failed: \(error.code) (\(error.message)\(sip))"
        @unknown default: return "Call ended" // a reason added by a newer SDK
        }
    }

    /// What to report to CallKit. `nil` when the end was performed through `CXEndCallAction` (fulfilling the action
    /// already told CallKit). A local end that bypassed CallKit is still reported so no stale system call remains.
    nonisolated static func cxEndedReason(
        _ reason: Call.EndReason,
        endedViaCallKit: Bool = true
    ) -> CXCallEndedReason? {
        switch reason {
        case .remoteHangup: return .remoteEnded
        case .noAnswer: return .unanswered
        case .busy, .rejected, .failed: return .failed
        case .localHangup, .cancelled: return endedViaCallKit ? nil : .remoteEnded
        @unknown default: return .failed
        }
    }
}
