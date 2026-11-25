//
// Copyright (c) 2026 Yolla Calls International OÜ
// Author: Sergei Popov
// SPDX-License-Identifier: MIT
//
// Part of the Yolla Voice example app; see the LICENSE file in the example's folder.
//

import Combine
import SwiftUI
import YollaVoiceSDK

struct InCallView: View {
    @Environment(AppModel.self) private var appModel
    let call: CallViewModel
    @State private var showKeypad = false
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(call.number).font(.title.weight(.semibold))
            Text(statusText).font(.headline).foregroundStyle(statusColor)
            if let callID = call.callID { Text(callID).font(.caption.monospaced()).foregroundStyle(.secondary) }
            if !call.warnings.isEmpty {
                HStack {
                    ForEach(call.warnings.map(\.rawValue).sorted(), id: \.self) { warning in
                        Text(warning).font(.caption2).padding(6).background(.orange.opacity(0.2), in: Capsule())
                    }
                }
            }
            if let stats = call.stats { statsLine(stats) }
            if let error = call.lastError { Text(error).font(.footnote).foregroundStyle(.red) }
            Spacer()

            if showKeypad {
                DTMFKeypadView(showsBackspace: false) { key in Task { await call.send(digit: key) } }
                    .padding(.horizontal, 32)
            } else {
                controls
            }

            Button {
                Task { await call.hangup() }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.title)
                    .frame(width: 72, height: 72)
                    .background(.red, in: Circle())
                    .foregroundStyle(.white)
            }
            .disabled(!call.phase.isActive)
            .padding(.bottom, 32)
        }
        .padding()
        .onReceive(ticker) { now = $0 }
        .onChange(of: call.phase) { _, phase in
            if case .ended = phase {
                // Long enough to read how the call ended, and for the SDK's tone to finish: closing the screen
                // releases the audio session when CallKit is off.
                Task {
                    try? await Task.sleep(for: max(.seconds(2), call.endToneDuration)); appModel.dismissCall(call)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            control(call.isMuted ? "mic.slash.fill" : "mic.fill", "Mute", active: call.isMuted) {
                Task { await call.toggleMute() }
            }
            control(showKeypad ? "circle.grid.3x3.fill" : "circle.grid.3x3", "Keypad", active: showKeypad) {
                showKeypad.toggle()
            }
            control(call.isOnHold ? "pause.circle.fill" : "pause.circle", "Hold", active: call.isOnHold) {
                Task { await call.toggleHold() }
            }
            VStack {
                AudioRouteButton().frame(width: 44, height: 44)
                Text("Audio").font(.caption)
            }
        }
        .disabled(call.phase != .connected)
    }

    private func control(
        _ symbol: String,
        _ title: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(
                        active ? Color.accentColor.opacity(0.25) : Color(.secondarySystemBackground),
                        in: Circle()
                    )
                Text(title).font(.caption)
            }
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        switch call.phase {
        case .connecting: return "Connecting…"
        case .ringing(let early): return early ? "Ringing (early media)" : "Ringing…"
        case .connected: return call.isOnHold ? "On hold" : duration
        case .reconnecting(let reason): return "Reconnecting (\(reason))…"
        case .ended(let reason, let error): return CallViewModel.describe(reason, error: error)
        }
    }

    private var statusColor: Color {
        switch call.phase {
        case .connected: return .green
        case .reconnecting: return .orange
        case .ended: return .secondary
        default: return .primary
        }
    }

    private var duration: String {
        guard let start = call.connectedAt else { return "Connected" }
        let seconds = Int(now.timeIntervalSince(start))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func statsLine(_ stats: CallStats) -> some View {
        let rtt = stats.sample.rttMs.map { String(format: "RTT %.0f ms", $0) } ?? "RTT –"
        let jitter = stats.sample.jitterMs.map { String(format: "jitter %.0f ms", $0) } ?? "jitter –"
        let loss = stats.sample.lossPercent.map { String(format: "loss %.1f%%", $0) } ?? "loss –"
        let mos = stats.sample.mos.map { String(format: "MOS %.1f", $0) } ?? "MOS –"
        let route = stats.media.candidateType.map { " · \($0)" } ?? ""
        return Text("\(rtt) · \(jitter) · \(loss) · \(mos)\(route)").font(.caption.monospaced()).foregroundStyle(
            .secondary
        )
    }
}
