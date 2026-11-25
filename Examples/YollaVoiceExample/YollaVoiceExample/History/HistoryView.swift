//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import SwiftUI

/// The calls placed from this app. A tap on a row calls the number again.
struct HistoryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var confirmingClear = false
    private var records: [CallRecord] { appModel.history.records }

    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { record in
                    Button {
                        Task { await appModel.placeCall(to: record.number) }
                    } label: {
                        row(record)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { appModel.history.remove(atOffsets: $0) }
            }
            .listStyle(.plain)
            .overlay {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No calls yet",
                        systemImage: "clock",
                        description: Text("The calls you place appear here. Tap one to call the number again.")
                    )
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) { confirmingClear = true }
                        .disabled(records.isEmpty)
                }
            }
            .confirmationDialog("Clear the call history?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { appModel.history.clear() }
            }
        }
    }

    private func row(_ record: CallRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.number).font(.body).foregroundStyle(record.failed ? .red : .primary)
                Text(Self.details(record)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text(record.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle()) // the whole row calls, not only its text
    }

    /// "Call ended · 1:05" for an answered call, the outcome alone for the others.
    nonisolated static func details(_ record: CallRecord) -> String {
        guard let duration = record.duration else { return record.outcome }
        let seconds = Int(duration.rounded())
        let time =
            seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
        return "\(record.outcome) · \(time)"
    }
}
