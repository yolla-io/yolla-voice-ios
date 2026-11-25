//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import Foundation
import Testing
import YollaVoiceSDK
@testable import YollaVoiceExample

@MainActor struct CallHistoryTests {
    func makeStore() -> CallHistoryStore {
        CallHistoryStore(defaults: UserDefaults(suiteName: "CallHistoryTests.\(UUID().uuidString)")!)
    }

    func record(_ number: String) -> CallRecord {
        CallRecord(
            number: number,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            duration: 5,
            outcome: "Call ended",
            failed: false
        )
    }

    @Test func historyIsNewestFirstAndSurvivesARestart() {
        let store = makeStore()
        let history = CallHistory(store: store)
        #expect(history.records.isEmpty)
        history.add(record("1"))
        history.add(record("2"))
        #expect(history.records.map(\.number) == ["2", "1"])
        #expect(CallHistory(store: store).records == history.records)
    }

    @Test func onlyTheLastCallsAreKept() {
        let store = makeStore()
        let history = CallHistory(store: store)
        for index in 0..<(CallHistory.capacity + 5) { history.add(record("\(index)")) }
        #expect(history.records.count == CallHistory.capacity)
        #expect(history.records.first?.number == "\(CallHistory.capacity + 4)")
        #expect(history.records.last?.number == "5")
        #expect(store.load().count == CallHistory.capacity)
    }

    @Test func removingAndClearingAreSaved() {
        let store = makeStore()
        let history = CallHistory(store: store)
        for number in ["1", "2", "3"] { history.add(record(number)) }
        history.remove(atOffsets: [0, 2])
        #expect(store.load().map(\.number) == ["2"])
        history.clear()
        #expect(history.records.isEmpty && store.load().isEmpty)
    }

    @Test func anAnsweredCallIsRecordedOnceWithItsDuration() {
        let viewModel = CallViewModel(uuid: UUID(), number: "4915112345678", logs: LogStore(), callKit: nil)
        var records: [CallRecord] = []
        viewModel.onEnded = { records.append($0) }
        viewModel.didConnect()
        viewModel.callDidDisconnect(reason: .remoteHangup, error: nil)
        viewModel.callDidDisconnect(reason: .remoteHangup, error: nil)
        #expect(records.count == 1)
        #expect(records.first?.number == "4915112345678")
        #expect(records.first?.duration != nil)
        #expect(records.first?.failed == false)
        #expect(records.first?.date == viewModel.startedAt)
    }

    @Test func aCallThatDidNotGoThroughIsRecordedAsFailed() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let busy = CallViewModel.record(number: "1", startedAt: start, connectedAt: nil, reason: .busy, error: nil)
        #expect(busy.failed && busy.duration == nil && busy.outcome == "Busy")
        let hungUp = CallViewModel.record(
            number: "1",
            startedAt: start,
            connectedAt: start.addingTimeInterval(2),
            endedAt: start.addingTimeInterval(67),
            reason: .localHangup,
            error: nil
        )
        #expect(!hungUp.failed && hungUp.duration == 65)
        #expect(HistoryView.details(hungUp) == "Call ended · 1:05")
        #expect(HistoryView.details(busy) == "Busy")
    }

    @Test func aCallThatCouldNotStartIsInTheHistory() async {
        let suite = "CallHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let model = AppModel(
            settingsStore: SettingsStore(defaults: defaults),
            historyStore: CallHistoryStore(defaults: defaults)
        )
        model.settings.tokenSource = .pasted("not a token")
        await model.placeCall(to: "4915112345678")
        #expect(model.alert != nil)
        #expect(model.history.records.count == 1)
        #expect(model.history.records.first?.number == "4915112345678")
        #expect(model.history.records.first?.failed == true)
    }
}
