//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import Foundation
import Observation

/// One call the app placed, as the History tab shows it.
nonisolated struct CallRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var number: String
    /// When the call was placed.
    var date: Date
    /// The time in conversation; nil for a call that was never answered.
    var duration: TimeInterval?
    /// How the call ended, in words: "Call ended", "Busy", or the error of a call that could not start.
    var outcome: String
    /// True for a call that did not go through: busy, unanswered, rejected or failed.
    var failed: Bool
}

/// Persists the call history as JSON in UserDefaults.
nonisolated struct CallHistoryStore: @unchecked Sendable { // UserDefaults is thread-safe but not marked Sendable
    private let defaults: UserDefaults
    private let key = "callHistory.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [CallRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CallRecord].self, from: data)) ?? []
    }

    func save(_ records: [CallRecord]) {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
    }
}

/// The calls the app placed, newest first. Only the last `capacity` are kept: UserDefaults is not a database.
@MainActor @Observable
final class CallHistory {
    static let capacity = 100
    private(set) var records: [CallRecord]
    private let store: CallHistoryStore

    init(store: CallHistoryStore = CallHistoryStore()) {
        self.store = store
        self.records = store.load()
    }

    func add(_ record: CallRecord) {
        records.insert(record, at: 0)
        if records.count > Self.capacity { records.removeLast(records.count - Self.capacity) }
        store.save(records)
    }

    func remove(atOffsets offsets: IndexSet) {
        // Not `remove(atOffsets:)` of SwiftUI: this file does without it.
        for index in offsets.sorted(by: >) { records.remove(at: index) }
        store.save(records)
    }

    func clear() {
        records.removeAll()
        store.save(records)
    }
}
