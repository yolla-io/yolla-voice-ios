//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import Foundation
import Foundation
import Observation

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let message: String
}

/// The app's own events: CallKit, the token request, call state changes, errors. The SDK's log is not here: the SDK
/// keeps it to itself and sends it to the platform.
@MainActor @Observable
final class LogStore {
    private(set) var entries: [LogEntry] = []
    private let capacity = 2000

    func app(_ message: String) {
        entries.append(LogEntry(date: Date(), message: message))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    func clear() { entries.removeAll() }

    var exportText: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return entries.map { "\(formatter.string(from: $0.date)) \($0.message)" }.joined(separator: "\n")
    }
}
