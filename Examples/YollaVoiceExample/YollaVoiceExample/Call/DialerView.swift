//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import SwiftUI
import YollaVoiceSDK

struct DialerView: View {
    @Environment(AppModel.self) private var appModel
    @State private var number = ""
    @State private var placing = false
    @FocusState private var numberFocused: Bool

    private var problems: [String] { appModel.settings.validate() }
    private var canCall: Bool { problems.isEmpty && !number.trimmingCharacters(in: .whitespaces).isEmpty && !placing }

    var body: some View {
        NavigationStack {
            // The content scrolls: with the keyboard up it does not fit the screen, and a stack that cannot scroll
            // would spread over the title. Without the keyboard it stays centred, as high as the screen.
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        TextField("Phone number", text: $number)
                            .keyboardType(.phonePad)
                            .font(.system(size: 32, weight: .light, design: .rounded))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.plain)
                            .padding(.vertical)
                            .focused($numberFocused)

                        DTMFKeypadView { key in
                            if key == "⌫" { if !number.isEmpty { number.removeLast() } } else { number.append(key) }
                        }

                        if let first = problems.first {
                            Text("Settings: \(first)").font(.footnote).foregroundStyle(.red)
                        }

                        Button {
                            numberFocused = false
                            placing = true
                            Task {
                                await appModel.placeCall(to: number); placing = false
                            }
                        } label: {
                            Label("Call", systemImage: "phone.fill")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(!canCall)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            // The phone pad has no return key: "Done" above it puts the keyboard away, and so does dragging it down.
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { numberFocused = false }
                }
            }
            .navigationTitle("Yolla Voice")
        }
    }
}
