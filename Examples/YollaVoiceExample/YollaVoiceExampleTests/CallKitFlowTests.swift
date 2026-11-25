//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import CallKit
import Foundation
import Testing
import YollaVoiceSDK
@testable import YollaVoiceExample

@MainActor final class FakeCallKit: CallKitControlling {
    var ended: [UUID] = []
    var muted: [(UUID, Bool)] = []
    var held: [(UUID, Bool)] = []
    var reportedEnds: [(UUID, CXCallEndedReason)] = []
    var connecting: [UUID] = []
    var connected: [UUID] = []
    var endCallError: (any Error)?
    func endCall(uuid: UUID) async throws {
        if let endCallError { throw endCallError }
        ended.append(uuid)
    }
    func setMuted(
        uuid: UUID,
        _ muted: Bool
    ) async throws { self.muted.append((uuid, muted)) }
    func setHeld(
        uuid: UUID,
        _ held: Bool
    ) async throws { self.held.append((uuid, held)) }
    func reportConnecting(_ uuid: UUID) { connecting.append(uuid) }
    func reportConnected(_ uuid: UUID) { connected.append(uuid) }
    func reportEnded(
        _ uuid: UUID,
        reason: CXCallEndedReason
    ) { reportedEnds.append((uuid, reason)) }
}

final class FakeCall: CallControlling, @unchecked Sendable {
    var hangups = 0
    var mutes: [Bool] = []
    var holds: [Bool] = []
    var digits: [String] = []
    var callID: String? { "call_01" }
    func setMuted(_ muted: Bool) async { mutes.append(muted) }
    func setOnHold(_ hold: Bool) async throws { holds.append(hold) }
    func sendDigits(_ digits: String) async throws { self.digits.append(digits) }
    func hangup() async { hangups += 1 }
    func stats() async -> CallStats { CallStats(media: .init(), sample: .init(), warnings: []) }
}

@MainActor struct CallKitFlowTests {
    /// Tones of 200 ms, so that the tests do not wait for the real three-second busy tone.
    static let shortTones: EndToneDurations = {
        let short = Duration.milliseconds(200)
        return EndToneDurations(ended: short, busy: short, noAnswer: short, failed: short)
    }()

    func makeVM(callKit: FakeCallKit?) -> CallViewModel {
        CallViewModel(uuid: UUID(), number: "4915112345678", logs: LogStore(), callKit: callKit, tones: Self.shortTones)
    }

    @Test func hangupWithCallKitGoesThroughEndCallAction() async {
        let ck = FakeCallKit(); let vm = makeVM(callKit: ck); let call = FakeCall()
        vm.attach(call)
        await vm.hangup()
        #expect(ck.ended == [vm.uuid] && call.hangups == 0) // the SDK is called from perform(CXEndCallAction)
        await vm.hangupFromCallKit()
        #expect(call.hangups == 1)
        vm.callDidDisconnect(reason: .localHangup, error: nil)
        #expect(ck.reportedEnds.isEmpty) // CallKit already knows: the action was fulfilled
    }

    @Test func aCallThatEndedBeforeConnectReturnedIsNotKept() async {
        let vm = makeVM(callKit: nil)
        weak var kept: FakeCall?
        do {
            let call = FakeCall(); kept = call
            vm.callDidDisconnect(reason: .failed, error: nil) // the end came before `connect` returned the call
            vm.attach(call)
        }
        #expect(kept == nil && vm.callID == "call_01")
    }

    @Test func theEndReportCanBeWaitedFor() async {
        let ck = FakeCallKit(); let vm = makeVM(callKit: ck)
        vm.callDidDisconnect(reason: .busy, error: nil)
        #expect(ck.reportedEnds.isEmpty) // the busy tone is playing
        await vm.endReport?.value
        #expect(ck.reportedEnds.map(\.1) == [.failed])
    }

    @Test func aHangupCallKitRefusedStillEndsTheCallAndIsReported() async {
        let ck = FakeCallKit(); let vm = makeVM(callKit: ck); let call = FakeCall()
        ck.endCallError = CancellationError()
        vm.attach(call)
        await vm.hangup()
        #expect(call.hangups == 1)
        vm.callDidDisconnect(reason: .localHangup, error: nil)
        await vm.endReport?.value
        #expect(ck.reportedEnds.map(\.1) == [.remoteEnded]) // no CXEndCallAction told CallKit: the app must
    }

    @Test func localEndThatBypassedCallKitIsStillReported() async throws {
        let ck = FakeCallKit(); let vm = makeVM(callKit: ck); let call = FakeCall()
        vm.attach(call)
        vm.callDidDisconnect(reason: .cancelled, error: nil) // e.g. SDK ended it locally without a CallKit action
        try await Task.sleep(for: .milliseconds(100)) // no tone follows a cancelled call: nothing to wait for
        #expect(ck.reportedEnds.map(\.1) == [.remoteEnded])
    }

    /// The CallKit end report is held for the SDK's end tone: reporting at once would deactivate the audio session mid-tone.
    @Test func callKitEndIsReportedAfterTheEndToneDelay() async throws {
        let ck = FakeCallKit(); let vm = makeVM(callKit: ck); let call = FakeCall()
        vm.attach(call)
        vm.didConnect()
        vm.callDidDisconnect(reason: .remoteHangup, error: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(ck.reportedEnds.isEmpty) // the 200 ms end tone is still playing
        try await Task.sleep(for: .milliseconds(400))
        #expect(ck.reportedEnds.map(\.1) == [.remoteEnded])
    }

    /// A call that was never answered ends with the reason the SDK gives, not with a generic failure.
    @Test func busyCallIsShownAsBusyAndReportedAfterTheBusyTone() async throws {
        let ck = FakeCallKit(); let vm = makeVM(callKit: ck)
        vm.attach(FakeCall())
        let error = VoiceError(code: "sip_486", message: "Busy Here", sipStatus: 486)
        vm.callDidFailToConnect(reason: .busy, error: error)
        #expect(vm.phase == .ended(reason: .busy, error: error))
        try await Task.sleep(for: .milliseconds(100))
        #expect(ck.reportedEnds.isEmpty) // the busy tone is still playing
        try await Task.sleep(for: .milliseconds(400))
        #expect(ck.reportedEnds.map(\.1) == [.failed])
    }

    @Test func unansweredCallIsReportedToCallKitAsUnanswered() async throws {
        let ck = FakeCallKit(); let vm = makeVM(callKit: ck)
        vm.attach(FakeCall())
        vm.callDidFailToConnect(
            reason: .noAnswer,
            error: VoiceError(code: "sip_480", message: "Temporarily Unavailable", sipStatus: 480)
        )
        try await Task.sleep(for: .milliseconds(500))
        #expect(ck.reportedEnds.map(\.1) == [.unanswered])
    }

    @Test func failureWithoutAReasonIsAFailure() {
        let vm = makeVM(callKit: nil)
        vm.callDidFailToConnect(reason: nil, error: .mediaFailed)
        #expect(vm.phase == .ended(reason: .failed, error: .mediaFailed))
    }

    /// A `Call` keeps its delegate, the view model: holding the ended call would keep both alive for good.
    @Test func endedCallIsReleased() {
        let vm = makeVM(callKit: nil)
        var call: FakeCall? = FakeCall()
        weak let released = call
        vm.attach(call!)
        call = nil
        #expect(released != nil)
        vm.callDidDisconnect(reason: .remoteHangup, error: nil)
        #expect(released == nil)
    }

    @Test func endToneDurationFollowsTheToneTheSDKPlays() {
        #expect(CallViewModel.endToneDuration(reason: .busy, wasConnected: false, tones: .sdk) >= .seconds(3))
        #expect(CallViewModel.endToneDuration(reason: .failed, wasConnected: false, tones: .sdk) >= .seconds(2))
        #expect(
            CallViewModel.endToneDuration(reason: .noAnswer, wasConnected: false, tones: .sdk) >= .milliseconds(800)
        )
        #expect(
            CallViewModel.endToneDuration(reason: .remoteHangup, wasConnected: true, tones: .sdk) >= .milliseconds(500)
        )
        #expect(CallViewModel.endToneDuration(reason: .remoteHangup, wasConnected: true, tones: .sdk) < .seconds(1))
        #expect(CallViewModel.endToneDuration(reason: .cancelled, wasConnected: false, tones: .sdk) == .zero)
    }

    @Test func endActionBeforeConnectFinishesHangsUpOnceAttached() async {
        let ck = FakeCallKit(); let vm = makeVM(callKit: ck); let call = FakeCall()
        await vm.hangupFromCallKit() // CXEndCallAction arrived while connect() is still running
        #expect(call.hangups == 0)
        vm.attach(call)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(call.hangups == 1)
    }

    @Test func muteAndHoldWithCallKitGoThroughActions() async throws {
        let ck = FakeCallKit(); let vm = makeVM(callKit: ck); let call = FakeCall()
        vm.attach(call)
        await vm.toggleMute()
        #expect(ck.muted.map(\.1) == [true] && call.mutes.isEmpty)
        await vm.applyMute(true)
        #expect(call.mutes == [true] && vm.isMuted)
        await vm.toggleHold()
        #expect(ck.held.map(\.1) == [true] && call.holds.isEmpty)
        try await vm.applyHold(true)
        #expect(call.holds == [true] && vm.isOnHold)
    }

    @Test func withoutCallKitCommandsGoStraightToTheCall() async {
        let vm = makeVM(callKit: nil); let call = FakeCall()
        vm.attach(call)
        await vm.toggleMute()
        await vm.hangup()
        #expect(call.mutes == [true] && call.hangups == 1)
    }
}
