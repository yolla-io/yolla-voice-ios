//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import Foundation

nonisolated enum TokenSource: Codable, Equatable {
    /// The app backend that issues a call token for each call.
    case url(String)
    /// A call token pasted by hand, for quick manual tests; a token is good for one call.
    case pasted(String)
}

/// What the app itself has to know: where its call tokens come from. The destination and the caller id are inside
/// the call token, and the SDK gets everything else from the platform.
/// Kept in UserDefaults for the example; keep tokens in the Keychain in production.
nonisolated struct Settings: Codable, Equatable {
    var tokenSource: TokenSource = .url(Settings.defaultTokenURL)
    var useCallKit = true

    /// The Yolla demo backend that issues call tokens; replace it with your own backend in Settings.
    static let defaultTokenURL = "https://demo.yolla.io/api/calls"
    static let `default` = Settings()

    /// Human-readable problems; empty means the settings can be used for a call.
    func validate() -> [String] {
        switch tokenSource {
        case .url(let url) where url.isEmpty:
            return ["Token URL or pasted token is required"]
        case .url(let url):
            if let parsed = URL(string: url), parsed.scheme?.hasPrefix("http") == true, parsed.host != nil { return [] }
            return ["Token URL is invalid"]
        case .pasted(let token) where token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return ["Token URL or pasted token is required"]
        case .pasted:
            return []
        }
    }
}
