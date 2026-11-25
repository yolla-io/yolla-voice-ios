//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import AVFAudio
import CallKit
import Foundation
import YollaVoiceSDK

/// What the call view model needs from CallKit; `CallKitManager` implements it, tests use a fake.
@MainActor
protocol CallKitControlling: AnyObject {
    func endCall(uuid: UUID) async throws
    func setMuted(
        uuid: UUID,
        _ muted: Bool
    ) async throws
    func setHeld(
        uuid: UUID,
        _ held: Bool
    ) async throws
    func reportConnecting(_ uuid: UUID)
    func reportConnected(_ uuid: UUID)
    func reportEnded(
        _ uuid: UUID,
        reason: CXCallEndedReason
    )
}

/// CallKit integration, owned by the app as the SDK recommends. User commands are requested as CX actions; the
/// provider performs them against the active call and forwards audio activation to `client.audioDevice`.
@MainActor
final class CallKitManager: NSObject, CXProviderDelegate, CallKitControlling {
    private let provider: CXProvider
    private let controller = CXCallController()
    weak var appModel: AppModel?
    private var startContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber]
        configuration.includesCallsInRecents = true
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil) // callbacks on the main queue
    }

    // MARK: Requests to the system

    /// Asks CallKit to start a call; the actual `connect` happens in `perform(CXStartCallAction)`. Returns when
    /// that action was fulfilled or failed.
    func startCall(
        uuid: UUID,
        number: String
    ) async throws {
        let handle = CXHandle(type: .phoneNumber, value: number)
        let action = CXStartCallAction(call: uuid, handle: handle)
        action.isVideo = false
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            startContinuations[uuid] = cont // stored before the request: perform() may run first
            controller.request(CXTransaction(action: action)) { error in
                if let error {
                    Task { @MainActor in self.startContinuations.removeValue(forKey: uuid)?.resume(throwing: error) }
                }
            }
        }
    }

    func endCall(uuid: UUID) async throws { try await request(CXEndCallAction(call: uuid)) }
    func setMuted(
        uuid: UUID,
        _ muted: Bool
    ) async throws {
        try await request(CXSetMutedCallAction(call: uuid, muted: muted))
    }
    func setHeld(
        uuid: UUID,
        _ held: Bool
    ) async throws {
        try await request(CXSetHeldCallAction(call: uuid, onHold: held))
    }

    private func request(_ action: CXAction) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            controller.request(CXTransaction(action: action)) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    // MARK: Reports from the SDK delegate

    func reportConnecting(_ uuid: UUID) { provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date()) }
    func reportConnected(_ uuid: UUID) { provider.reportOutgoingCall(with: uuid, connectedAt: Date()) }
    func reportEnded(
        _ uuid: UUID,
        reason: CXCallEndedReason
    ) {
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
    }

    private func finishStart(
        _ uuid: UUID,
        error: Error?
    ) {
        guard let cont = startContinuations.removeValue(forKey: uuid) else { return }
        if let error { cont.resume(throwing: error) } else { cont.resume() }
    }

    // MARK: CXProviderDelegate (main queue)

    nonisolated func providerDidReset(_ provider: CXProvider) {
        MainActor.assumeIsolated {
            appModel?.logs.app("[callkit] providerDidReset")
            for uuid in Array(startContinuations.keys) { finishStart(uuid, error: CancellationError()) }
            _ = Task { await appModel?.disconnect() }
        }
    }

    nonisolated func provider(
        _ provider: CXProvider,
        perform action: CXStartCallAction
    ) {
        MainActor.assumeIsolated {
            appModel?.logs.app("[callkit] perform start")
            _ = Task {
                do {
                    try await appModel?.performStart(uuid: action.callUUID, number: action.handle.value)
                    let update = CXCallUpdate()
                    update.remoteHandle = action.handle
                    update.supportsHolding = true
                    update.supportsDTMF = true
                    update.supportsGrouping = false
                    update.supportsUngrouping = false
                    update.hasVideo = false
                    self.provider.reportCall(with: action.callUUID, updated: update)
                    action.fulfill()
                    self.reportConnecting(action.callUUID) // the call is on its way
                    self.finishStart(action.callUUID, error: nil)
                } catch {
                    action.fail()
                    self.finishStart(action.callUUID, error: error)
                }
            }
        }
    }

    nonisolated func provider(
        _ provider: CXProvider,
        perform action: CXEndCallAction
    ) {
        MainActor.assumeIsolated {
            appModel?.logs.app("[callkit] perform end")
            guard let call = appModel?.activeCall, call.uuid == action.callUUID else { action.fail(); return }
            _ = Task {
                await call.hangupFromCallKit(); action.fulfill()
            }
        }
    }

    nonisolated func provider(
        _ provider: CXProvider,
        perform action: CXSetMutedCallAction
    ) {
        MainActor.assumeIsolated {
            guard let call = appModel?.activeCall, call.uuid == action.callUUID else { action.fail(); return }
            _ = Task {
                await call.applyMute(action.isMuted); action.fulfill()
            }
        }
    }

    nonisolated func provider(
        _ provider: CXProvider,
        perform action: CXSetHeldCallAction
    ) {
        MainActor.assumeIsolated {
            guard let call = appModel?.activeCall, call.uuid == action.callUUID else { action.fail(); return }
            _ = Task {
                do { try await call.applyHold(action.isOnHold); action.fulfill() } catch { action.fail() }
            }
        }
    }

    nonisolated func provider(
        _ provider: CXProvider,
        timedOutPerforming action: CXAction
    ) {
        MainActor.assumeIsolated { appModel?.logs.app("[callkit] timed out performing \(type(of: action))") }
    }

    nonisolated func provider(
        _ provider: CXProvider,
        didActivate audioSession: AVAudioSession
    ) {
        MainActor.assumeIsolated {
            appModel?.logs.app("[callkit] didActivate audio")
            appModel?.client?.audioDevice.isEnabled = true
        }
    }

    nonisolated func provider(
        _ provider: CXProvider,
        didDeactivate audioSession: AVAudioSession
    ) {
        MainActor.assumeIsolated {
            appModel?.logs.app("[callkit] didDeactivate audio")
            appModel?.client?.audioDevice.isEnabled = false
        }
    }
}
