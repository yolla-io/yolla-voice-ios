//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        TabView {
            DialerView().tabItem { Label("Dialer", systemImage: "phone") }
            HistoryView().tabItem { Label("History", systemImage: "clock") }
            LogsView().tabItem { Label("Logs", systemImage: "doc.text") }
            SettingsView().tabItem { Label("Settings", systemImage: "gear") }
        }
        // Bound to the model, not a local flag: dismissing the sheet never ends the call, and it reopens while active.
        .fullScreenCover(item: $appModel.activeCall) { call in
            InCallView(call: call)
        }
        .alert("Error", isPresented: Binding(get: { appModel.alert != nil }, set: { if !$0 { appModel.alert = nil } }))
        {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appModel.alert ?? "")
        }
    }
}
