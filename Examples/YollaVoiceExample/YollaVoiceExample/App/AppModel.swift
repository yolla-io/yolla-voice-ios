//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import AVFAudio
import Foundation
import Observation
import YollaVoiceSDK

/// Owns the SDK client, settings, logs, the call history, CallKit and the active call.
@MainActor @Observable
final class AppModel {
    var settings: Settings {
        didSet { settingsStore.save(settings) }
    }
    let logs = LogStore()
    let history: CallHistory
    let callKit = CallKitManager()
    var activeCall: CallViewModel?
    var alert: String?
    private let settingsStore: SettingsStore
    private(set) var client: VoiceClient?
    /// Call tokens between `placeCall`, which gets them, and `performStart`, which CallKit triggers, by call UUID.
    private var pendingTokens: [UUID: String] = [:]
    /// True from the tap on Call until the call is on its way or has failed: a second tap must not start another.
    private var isPlacingCall = false
    /// The last call, kept after its screen is gone for its end report to CallKit (see `CallViewModel.endReport`).
    private var lastCall: CallViewModel?
    /// Set when a failed connect took the call screen down; `placeCall` then waits before showing the alert.
    private var callScreenClosedByFailure = false
    /// True once the call `placeCall` is at work on has its line in the history: a call that fails while it is set
    /// up is written there either by its view model (the SDK reported the end) or by `placeCall`, never by both.
    private var attemptRecorded = false

    init(
        settingsStore: SettingsStore = SettingsStore(),
        historyStore: CallHistoryStore = CallHistoryStore()
    ) {
        self.settingsStore = settingsStore
        self.history = CallHistory(store: historyStore)
        self.settings = settingsStore.load()
        callKit.appModel = self
    }

    /// Entry point from the dialer and from the history: validates settings, then goes through CallKit or straight to the SDK.
    func placeCall(to number: String) async {
        let problems = settings.validate()
        guard problems.isEmpty else { alert = problems.joined(separator: "\n"); return }
        guard !number.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard !isPlacingCall, activeCall == nil || activeCall?.phase.isActive == false else {
            alert = "A call is already active"; return
        }
        isPlacingCall = true
        defer { isPlacingCall = false }
        attemptRecorded = false
        let placedAt = Date()
        logs.app("call \(number) via \(settings.useCallKit ? "CallKit" : "direct")")
        do {
            // The token comes first: it carries the call id, and the call's UUID, which CallKit wants before the
            // call exists, is made from it.
            let token: String
            do {
                token = try await TokenProvider(settings: settings).token(to: number)
            } catch {
                logs.app("[token] \(describe(error))")
                throw error
            }
            let uuid = try VoiceClient.callUUID(for: token)
            pendingTokens[uuid] = token
            defer { pendingTokens[uuid] = nil }
            if settings.useCallKit {
                // CallKit has the previous call until its end is reported, after the end tone: a start request
                // before that is refused, and with a reused token (the same UUID) the late report would end this call.
                await lastCall?.endReport?.value
                try await callKit.startCall(uuid: uuid, number: number)
            } else {
                // Without CallKit the app owns the audio session: activate it and enable SDK audio before connecting.
                let client = try makeClientIfNeeded()
                try AVAudioSession.sharedInstance().setActive(true)
                client.audioDevice.isEnabled = true
                do { try await performStart(uuid: uuid, number: number) } catch { releaseDirectAudio(); throw error }
            }
        } catch {
            // An alert set while the call screen is still sliding away is dropped by SwiftUI: let it close first.
            if callScreenClosedByFailure {
                callScreenClosedByFailure = false
                try? await Task.sleep(for: .milliseconds(700))
            }
            // A call that could not start (no token, CallKit refused it, the connect failed) is in the history too.
            if !attemptRecorded {
                attemptRecorded = true
                history.add(
                    CallRecord(number: number, date: placedAt, duration: nil, outcome: describe(error), failed: true)
                )
            }
            alert = describe(error)
        }
    }

    /// Creates the view model and connects. Called from `CXStartCallAction` or directly without CallKit.
    func performStart(
        uuid: UUID,
        number: String
    ) async throws {
        let client = try makeClientIfNeeded()
        guard let token = pendingTokens.removeValue(forKey: uuid) else { throw TokenError.missing }
        let viewModel = CallViewModel(
            uuid: uuid,
            number: number,
            logs: logs,
            callKit: settings.useCallKit ? callKit : nil
        )
        viewModel.onEnded = { [weak self] record in
            self?.attemptRecorded = true
            self?.history.add(record)
        }
        activeCall = viewModel
        lastCall = viewModel
        do {
            // The token carries the destination and the caller id; the SDK gets everything else from the platform.
            let call = try await client.connect(callToken: token, delegate: viewModel)
            viewModel.attach(call)
        } catch {
            // `placeCall` writes this failure to the history, unless the SDK has already reported the call's end.
            viewModel.onEnded = nil
            activeCall = nil
            callScreenClosedByFailure = true
            logs.app("connect failed: \(describe(error))")
            throw error
        }
    }

    /// Called by the in-call screen once the call has ended and the closing delay elapsed.
    func dismissCall(_ call: CallViewModel) {
        guard activeCall === call else { return }
        activeCall = nil
        if !settings.useCallKit { releaseDirectAudio() }
    }

    func disconnect() async {
        await client?.disconnect()
        releaseDirectAudio()
        client = nil
        activeCall = nil
    }

    private func releaseDirectAudio() {
        client?.audioDevice.isEnabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func makeClientIfNeeded() throws -> VoiceClient {
        if let client { return client }
        // Nothing to configure: the call token and the platform provide everything. The SDK keeps its own log.
        let client = VoiceClient()
        try client.audioDevice.configure()
        self.client = client
        return client
    }

    private func describe(_ error: Error) -> String {
        if let voiceError = error as? VoiceError { return "\(voiceError.code): \(voiceError.message)" }
        if let urlError = error as? URLError {
            let host = urlError.failingURL?.host.map { " (\($0))" } ?? ""
            return "Token request failed\(host): \(urlError.localizedDescription)"
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
