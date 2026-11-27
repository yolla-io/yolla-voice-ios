# Yolla Voice SDK for iOS

Place phone calls from an iOS app through the Yolla voice platform. The SDK carries signalling and audio; your app
owns the user interface and CallKit.

- Outgoing calls to phone numbers, with mute, hold, DTMF and automatic reconnection when the network changes
- Works with CallKit or without it
- Call quality statistics and warnings
- Ringback, busy and end tones, with no audio files to ship

Version 0.1.1.

## Requirements

- iOS 17 or later, Xcode 26 or later
- A Yolla account, and a backend of yours that asks the Yolla platform for call tokens

The SDK is a binary framework; WebRTC comes with it as a package dependency.

## Installation

Swift Package Manager, in Xcode (**File → Add Package Dependencies…**) or in `Package.swift`:

```swift
.package(url: "https://github.com/yolla-io/yolla-voice-ios", from: "0.1.1")
```

Add the `YollaVoiceSDK` product to your app target, and in the app's `Info.plist` set:

- `NSMicrophoneUsageDescription`: the text iOS shows when it asks for the microphone;
- the background modes `audio` and `voip` (**Signing & Capabilities → Background Modes**).

## How a call works

```
  your app  ──  "call +4915112345678"  ──▶  your backend  ──  API key  ──▶  Yolla platform
  your app  ◀──────  call token  ─────────  your backend  ◀──  call token  ──  Yolla platform
  your app  ──  connect(callToken:)  ──────────────────────────────────────▶  Yolla platform
```

1. Your backend asks the Yolla platform for a **call token**: a short-lived JWT issued for one call, with the
   destination and the caller ID inside. API keys stay on your backend.
2. Your app gets the token from your backend and passes it to the SDK.
3. The SDK places the call and reports its progress to your delegate.

## Quick start

The shortest working integration: one class that places a call and prints what happens to it.

```swift
import AVFAudio
import YollaVoiceSDK

@MainActor
final class Dialer: CallDelegate {
    let client = VoiceClient()
    private var call: Call?

    func dial(_ number: String) async throws {
        let token = try await fetchCallToken(to: number) // from your backend, one per call

        try client.audioDevice.configure()
        try AVAudioSession.sharedInstance().setActive(true) // with CallKit, CallKit does this
        client.audioDevice.isEnabled = true

        call = try await client.connect(callToken: token, delegate: self)
    }

    func hangup() async {
        await call?.hangup()
    }

    func callDidStartRinging(
        _ call: Call,
        earlyMedia: Bool
    ) { print("ringing") }
    func callDidConnect(_ call: Call) { print("connected") }
    func callDidFailToConnect(
        _ call: Call,
        error: VoiceError
    ) { print("failed:", error.code, error.message) }
    func callDidDisconnect(
        _ call: Call,
        reason: Call.EndReason,
        error: VoiceError?
    ) { print("ended:", reason) }
    func callIsReconnecting(
        _ call: Call,
        error: VoiceError
    ) {}
    func callDidReconnect(_ call: Call) {}
    func callDidReceiveQualityWarnings(
        _ call: Call,
        current: Set<CallQualityWarning>,
        previous: Set<CallQualityWarning>
    ) {}
}
```

`fetchCallToken(to:)` is your request to your backend; the guide has
[an example](Documentation/Integration.md#3-the-call-token). Keep one `Dialer` for the app and call
`try await dialer.dial("+4915112345678")`.

This is enough to hear a call, and no more: it does not release the audio session after the call or handle a
hang-up during set-up. A real app starts its calls through CallKit, so that they appear on the lock screen
and survive interruptions: that is the [CallKit section](Documentation/Integration.md#5-callkit) of the guide, with
a complete class to copy.

## Documentation

The [integration guide](Documentation/Integration.md) goes through everything in order:

| Section | What it answers |
|---|---|
| [Project setup](Documentation/Integration.md#1-project-setup) | What goes into the project and `Info.plist` |
| [The client](Documentation/Integration.md#2-the-client) | Where to create `VoiceClient` and how long to keep it |
| [The call token](Documentation/Integration.md#3-the-call-token) | What the app asks your backend for, and when |
| [Placing a call](Documentation/Integration.md#4-placing-a-call) | `connect`, the delegate, the order of events |
| [CallKit](Documentation/Integration.md#5-callkit) | A complete `CXProviderDelegate`: start, end, mute, hold, audio |
| [Without CallKit](Documentation/Integration.md#6-without-callkit) | Managing the audio session yourself |
| [During a call](Documentation/Integration.md#7-during-a-call) | Mute, hold, DTMF, audio route, reconnection, quality |
| [Tones](Documentation/Integration.md#8-tones) | Which tones the SDK plays, when, and how long they last |
| [Errors](Documentation/Integration.md#9-errors) | Every `VoiceError` code and what to do about it |
| [Troubleshooting](Documentation/Integration.md#10-troubleshooting) | No sound, dropped calls, what to send to support |

## Example app

[`Examples/YollaVoiceExample`](Examples/YollaVoiceExample) is a complete SwiftUI app: dialer, in-call screen with
mute, hold and a DTMF keypad, CallKit, audio routes, quality indicators. Open `YollaVoiceExample.xcodeproj`; it uses
the SDK from this repository. Its [README](Examples/YollaVoiceExample/README.md) says how to run it and which file
shows what.

## Privacy

The framework includes a privacy manifest (`PrivacyInfo.xcprivacy`). To place calls the SDK sends the platform the
dialled number, a device identifier it generates and keeps in the Keychain, device information
(model, OS version, language, country, time zone, network type, whether the device is jailbroken), app information
(bundle ID, version, build), call quality statistics and, when the platform asks for it, its diagnostic log. The
log is kept in the app's `Library/Logs/YollaVoice` folder (at most 5 MB, secrets masked) and contains dialled
numbers and IP addresses. The SDK does not track users.

## Support

When you report a problem, include the SDK version (`VoiceSDK.version`), the call's `Call.callID`, when the call was
made, and the `code` and `message` of the `VoiceError` if there was one. The SDK has no logging API: in your app, log
what `CallDelegate` and `VoiceError` tell you.

## License

The SDK is proprietary software of Yolla Calls International OÜ and may be used only under a commercial agreement with
Yolla Calls International OÜ; see [LICENSE](LICENSE). The example app is under the [MIT License](Examples/YollaVoiceExample/LICENSE).
