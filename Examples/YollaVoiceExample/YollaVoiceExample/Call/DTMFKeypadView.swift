//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import SwiftUI

/// 12-key pad plus backspace; `onKey` receives "0"–"9", "*", "#" or "⌫".
struct DTMFKeypadView: View {
    var showsBackspace = true
    var onKey: (String) -> Void

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in button(key) }
                }
            }
            if showsBackspace {
                HStack(spacing: 10) {
                    Spacer().frame(maxWidth: .infinity)
                    button("⌫")
                    Spacer().frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func button(_ key: String) -> some View {
        Button {
            onKey(key)
        } label: {
            Text(key)
                .font(.title2)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(.secondarySystemBackground), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
