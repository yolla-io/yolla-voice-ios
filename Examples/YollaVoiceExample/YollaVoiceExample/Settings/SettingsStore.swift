//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import Foundation

/// Persists `Settings` as JSON in UserDefaults.
nonisolated struct SettingsStore: @unchecked Sendable { // UserDefaults is thread-safe but not marked Sendable
    private let defaults: UserDefaults
    private let key = "settings.v2" // v1 had another shape; it is left behind, not migrated

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> Settings {
        guard let data = defaults.data(forKey: key), let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return .default }
        return settings
    }

    func save(_ settings: Settings) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }
}
