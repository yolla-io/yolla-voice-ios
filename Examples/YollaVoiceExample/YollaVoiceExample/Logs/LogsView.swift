//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import SwiftUI

struct LogsView: View {
    @Environment(AppModel.self) private var appModel
    private var visible: [LogEntry] { appModel.logs.entries }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(visible) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date.formatted(date: .omitted, time: .standard))
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(entry.message).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    .id(entry.id)
                }
                .listStyle(.plain)
                .onChange(of: visible.last?.id) { _, _ in
                    if let last = visible.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .overlay {
                if visible.isEmpty {
                    ContentUnavailableView(
                        "No events yet",
                        systemImage: "doc.text",
                        description: Text(
                            "The app's own events appear here. The SDK's log is sent to the platform, not shown in the app."
                        )
                    )
                }
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: appModel.logs.exportText) { Image(systemName: "square.and.arrow.up") }
                    Button(role: .destructive) {
                        appModel.logs.clear()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }
}
