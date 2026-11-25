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

/// Serves canned responses for the token endpoint.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    /// URLSession hands the body to a URLProtocol as a stream, not as `httpBody`.
    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct TokenProviderTests {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }()

    func settings(_ source: TokenSource) -> Settings {
        var s = Settings.default; s.tokenSource = source; return s
    }

    @Test func postsDialedNumberAndReadsCallToken() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://backend.example.com/calls")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer demo-token-1")
            let body = try? JSONSerialization.jsonObject(with: StubURLProtocol.body(of: request)) as? [String: String]
            #expect(body == ["to": "43242343243242"])
            return (200, Data("{\"callToken\":\"jwt-1\"}".utf8))
        }
        let provider = TokenProvider(
            settings: settings(.url("https://backend.example.com/calls")),
            bearerToken: "demo-token-1",
            session: Self.session
        )
        #expect(try await provider.token(to: "43242343243242") == "jwt-1")
    }

    @Test func httpErrorAndBadBodyAreReported() async {
        StubURLProtocol.handler = { _ in (500, Data("oops".utf8)) }
        let provider = TokenProvider(
            settings: settings(.url("https://backend.example.com/voice-token")),
            bearerToken: "demo-token-1",
            session: Self.session
        )
        await #expect(throws: TokenError.http(500)) { _ = try await provider.token(to: "1") }
        StubURLProtocol.handler = { _ in (200, Data("{\"token\":\"old-shape\"}".utf8)) }
        await #expect(throws: TokenError.invalidResponse) { _ = try await provider.token(to: "1") }
    }

    /// Without the demo token (the build setting is still the placeholder) nothing is sent.
    @Test func missingDemoTokenIsReportedBeforeAnyRequest() async {
        StubURLProtocol.handler = { _ in
            Issue.record("No request is expected without the demo token")
            return (401, Data())
        }
        let provider = TokenProvider(
            settings: settings(.url("https://backend.example.com/calls")),
            bearerToken: nil,
            session: Self.session
        )
        await #expect(throws: TokenError.demoTokenNotSet) { _ = try await provider.token(to: "1") }
    }

    @Test func placeholderAndEmptyBuildSettingAreNoToken() {
        #expect(TokenProvider.configuredToken(nil) == nil)
        #expect(TokenProvider.configuredToken("") == nil)
        #expect(TokenProvider.configuredToken("  ") == nil)
        #expect(TokenProvider.configuredToken(TokenProvider.demoTokenPlaceholder) == nil)
        #expect(TokenProvider.configuredToken(" abc123\n") == "abc123")
    }

    /// A pasted call token needs no demo token.
    @Test func pastedTokenIsReturnedTrimmed() async throws {
        #expect(
            try await TokenProvider(settings: settings(.pasted("  jwt-2\n")), bearerToken: nil).token(to: "1")
                == "jwt-2"
        )
        await #expect(throws: TokenError.missing) {
            _ = try await TokenProvider(settings: settings(.pasted("  ")), bearerToken: nil).token(to: "1")
        }
    }
}
