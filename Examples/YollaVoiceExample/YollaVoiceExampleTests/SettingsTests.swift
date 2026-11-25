//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import Foundation
import Testing
@testable import YollaVoiceExample

struct SettingsTests {
    @Test func roundTripsThroughStore() throws {
        let suite = "SettingsTests.\(UUID().uuidString)"
        let store = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        var settings = Settings.default
        settings.tokenSource = .pasted("jwt")
        settings.useCallKit = false
        store.save(settings)
        #expect(store.load() == settings)
        #expect(
            SettingsStore(defaults: UserDefaults(suiteName: "SettingsTests.empty.\(UUID().uuidString)")!).load()
                == Settings.default
        )
    }

    @Test func defaultsAreReadyForACall() {
        #expect(Settings.default.tokenSource == .url("https://demo.yolla.io/api/calls"))
        #expect(Settings.default.validate().isEmpty)
    }

    @Test func validation() {
        var s = Settings.default
        s.tokenSource = .url("")
        #expect(s.validate() == ["Token URL or pasted token is required"])
        s.tokenSource = .url("not a url")
        #expect(s.validate() == ["Token URL is invalid"])
        s.tokenSource = .url("https://backend.example.com/calls")
        #expect(s.validate().isEmpty)
        s.tokenSource = .pasted(" \n")
        #expect(s.validate() == ["Token URL or pasted token is required"])
        s.tokenSource = .pasted("jwt")
        #expect(s.validate().isEmpty)
    }
}
