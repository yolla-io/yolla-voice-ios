//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var draft = Settings.default
    @State private var tokenMode = 0 // 0 = URL, 1 = pasted
    @State private var tokenURL = ""
    @State private var pastedToken = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Call token") {
                    Picker("Source", selection: $tokenMode) {
                        Text("Token URL").tag(0); Text("Token").tag(1)
                    }.pickerStyle(.segmented)
                    switch tokenMode {
                    case 0:
                        TextField(Settings.defaultTokenURL, text: $tokenURL).keyboardType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text(
                            "Before each call the app sends POST <url> with {\"to\": \"<number>\"} and expects {\"callToken\": \"…\"}"
                        ).font(.footnote).foregroundStyle(.secondary)
                    default:
                        TextField("Call token (one per call)", text: $pastedToken, axis: .vertical).lineLimit(3...6)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("The call goes to the number inside the token, not the one typed in the dialer.").font(
                            .footnote
                        ).foregroundStyle(.secondary)
                    }
                }
                Section("Call") {
                    Toggle("Use CallKit", isOn: $draft.useCallKit)
                }
                Section {
                    Button("Save") { save() }.frame(maxWidth: .infinity)
                    if !draft.validate().isEmpty {
                        Text(draft.validate().joined(separator: "\n")).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text(
                        "The destination and the caller ID are inside the call token; the app has nothing else to set up. Settings are stored in UserDefaults for this example; keep tokens in the Keychain in production."
                    )
                }
            }
            .navigationTitle("Settings")
            .onAppear(perform: load)
        }
    }

    private func load() {
        draft = appModel.settings
        switch draft.tokenSource {
        case .url(let url): tokenMode = 0; tokenURL = url
        case .pasted(let token): tokenMode = 1; pastedToken = token
        }
    }

    private func save() {
        switch tokenMode {
        case 0: draft.tokenSource = .url(tokenURL.trimmingCharacters(in: .whitespaces))
        default: draft.tokenSource = .pasted(pastedToken)
        }
        appModel.settings = draft
        appModel.logs.app("settings saved")
    }
}
