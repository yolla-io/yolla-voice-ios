//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import Foundation

nonisolated enum TokenError: Error, Equatable, LocalizedError {
    case missing
    case demoTokenNotSet
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missing: return "No token: set a Token URL or paste a token in Settings"
        case .demoTokenNotSet:
            return
                "No demo token: set YOLLA_VOICE_DEMO_TOKEN in Config/Local.xcconfig and build again, or paste a call token in Settings"
        case .http(let status): return "Token endpoint returned HTTP \(status)"
        case .invalidResponse: return "Token endpoint did not return {\"callToken\": …}"
        }
    }
}

/// Supplies the call token for `VoiceClient`: from the app backend (`POST <url>` with `{"to": …}`) or a pasted JWT.
nonisolated struct TokenProvider: Sendable {
    /// What the build setting holds until a token is set.
    static let demoTokenPlaceholder = "YOUR_DEMO_TOKEN"

    /// The demo backend's credential: the bearer token its token endpoint expects. It is not in the code: it comes
    /// from the build setting `YOLLA_VOICE_DEMO_TOKEN` (`Config/Example.xcconfig`, set in the git-ignored
    /// `Config/Local.xcconfig`) through Info.plist. `nil` until it is set. A production app authorises this request
    /// with the user's own session instead.
    static let demoToken = configuredToken(Bundle.main.object(forInfoDictionaryKey: "YollaVoiceDemoToken") as? String)

    /// The build setting's value as a token: nothing when it is empty or still the placeholder.
    static func configuredToken(_ raw: String?) -> String? {
        guard let token = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty,
            token != demoTokenPlaceholder
        else { return nil }
        return token
    }

    private let settings: Settings
    private let bearerToken: String?
    private let session: URLSession

    init(
        settings: Settings,
        bearerToken: String? = TokenProvider.demoToken,
        session: URLSession = .shared
    ) {
        self.settings = settings
        self.bearerToken = bearerToken
        self.session = session
    }

    /// `number` is the dialed number, sent to the backend as typed; a pasted token ignores it.
    func token(to number: String) async throws -> String {
        switch settings.tokenSource {
        case .pasted(let token):
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw TokenError.missing }
            return trimmed
        case .url(let raw):
            guard let url = URL(string: raw) else { throw TokenError.missing }
            // Without the token the backend would only answer 401: say what is missing instead.
            guard let bearerToken else { throw TokenError.demoTokenNotSet }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(["to": number])
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw TokenError.http(status) }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let token = json["callToken"] as? String, !token.isEmpty
            else {
                throw TokenError.invalidResponse
            }
            return token
        }
    }
}
