# Integrating the Yolla Voice SDK

This guide takes an iOS app from an empty project to phone calls with CallKit. The code is complete: the classes
below can be copied into an app as they are. The [example app](../Examples/YollaVoiceExample) is the same integration
with a user interface on top.

1. [Project setup](#1-project-setup)
2. [The client](#2-the-client)
3. [The call token](#3-the-call-token)
4. [Placing a call](#4-placing-a-call)
5. [CallKit](#5-callkit)
6. [Without CallKit](#6-without-callkit)
7. [During a call](#7-during-a-call)
8. [Tones](#8-tones)
9. [Errors](#9-errors)
10. [Troubleshooting](#10-troubleshooting)

## 1. Project setup

Add the package as the [README](../README.md#installation) says, and add the `YollaVoiceSDK` product to the app
target. WebRTC comes with it as a package dependency.

The app target needs three things in its `Info.plist` (target → **Info** and **Signing & Capabilities → Background
Modes** in Xcode):

| Key | Value | Why |
|---|---|---|
| `NSMicrophoneUsageDescription` | Your text, for example "Needed to talk during calls." | iOS shows it when the microphone is first used. Without the key the app is terminated on the first call. |
| `UIBackgroundModes` | `audio` | The call keeps its audio when the app goes to the background or the screen locks. |
| `UIBackgroundModes` | `voip` | Required for CallKit calls. |

The SDK needs iOS 17 or later and Xcode 26 or later.

## 2. The client

`VoiceClient` is the entry point. Create one for the whole app and keep it: it holds the audio device and the active
call. There is nothing to configure, and no account data goes into the app.

```swift
import Foundation
import YollaVoiceSDK

@MainActor
final class VoiceService {
    static let shared = VoiceService()

    /// One client for the whole app.
    let client = VoiceClient()
    private var isAudioConfigured = false

    /// Sets the audio session up for voice calls. Call it before the first call; it does not activate the session.
    func prepare() throws {
        guard !isAudioConfigured else { return }
        try client.audioDevice.configure()
        isAudioConfigured = true
    }
}
```

`audioDevice.configure()` sets the shared `AVAudioSession` to the play-and-record category in voice-chat mode, with
Bluetooth allowed. If your app plays other audio, call `prepare()` when the user starts a call, not at launch.

Creating the client does not use the network. A client places one call at a time: a second `connect` while a call is
active throws `call_in_progress`.

`VoiceSDK.version` is the version of the SDK in the app.

## 3. The call token

Every call needs a **call token**: a short-lived JWT that the Yolla platform issues for one call. The destination
number and the caller ID are inside the token, so the app cannot change them.

```
  your app  ──  "call +4915112345678"  ──▶  your backend  ──  API key  ──▶  Yolla platform
  your app  ◀──────  call token  ─────────  your backend  ◀──  call token  ──  Yolla platform
  your app  ──  connect(callToken:)  ──────────────────────────────────────▶  Yolla platform
```

- The API key lives on your backend only. Never ship it in the app.
- Your backend decides whether this user may call this number, then asks the platform for the token.
- Ask for a token immediately before each call. A token is for one call: do not store or reuse it.

How the app talks to your backend is yours to design. A minimal version:

```swift
struct CallTokenResponse: Decodable {
    let callToken: String
}

/// Asks your backend for a token for one call to `number`.
func fetchCallToken(
    to number: String,
    userSession: String
) async throws -> String {
    var request = URLRequest(url: URL(string: "https://api.example.com/calls")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(userSession)", forHTTPHeaderField: "Authorization") // your own user authorisation
    request.httpBody = try JSONEncoder().encode(["to": number])

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
        throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(CallTokenResponse.self, from: data).callToken
}
```

The snippets below call it as `fetchCallToken(to:userSession:)` with `currentUserSession()` standing for however
your app identifies its signed-in user.

## 4. Placing a call

```swift
let call = try await client.connect(callToken: token, delegate: self)
```

- `callToken` is the token from your backend.
- `delegate` receives the call's events. The `Call` holds its delegate for as long as the `Call` object exists, so
  drop your reference to the `Call` when it ends: a delegate that keeps its ended call keeps itself alive.

`connect` asks for microphone permission if the user has not answered yet, sets the call up and returns a `Call` as
soon as the call is on its way. It throws a `VoiceError` when the call cannot start at all: the token is not valid,
the microphone is denied, the platform cannot be reached, another call is active. In that case no delegate method is
called.

### Call events

`CallDelegate` has seven methods, all called on the main actor:

```swift
func callDidStartRinging(_ call: Call, earlyMedia: Bool)
func callDidConnect(_ call: Call)
func callIsReconnecting(_ call: Call, error: VoiceError)
func callDidReconnect(_ call: Call)
func callDidFailToConnect(_ call: Call, error: VoiceError)
func callDidDisconnect(_ call: Call, reason: Call.EndReason, error: VoiceError?)
func callDidReceiveQualityWarnings(_ call: Call, current: Set<CallQualityWarning>, previous: Set<CallQualityWarning>)
```

A call ends with exactly one of `callDidFailToConnect` and `callDidDisconnect`:

| What happened | Events, in order |
|---|---|
| Answered, then someone hung up | `callDidStartRinging` → `callDidConnect` → `callDidDisconnect` |
| Busy, not answered, rejected, failed before the answer | `callDidStartRinging` (if it rang) → `callDidFailToConnect` |
| You called `hangup()` before the answer | `callDidDisconnect` with the reason `.cancelled` |
| The network changed during the call | `callIsReconnecting` → `callDidReconnect`, or `callDidDisconnect` with `.failed` |

`callDidStartRinging` comes once at most, and not at all for a call that is answered without ringing.
`earlyMedia: true` means the network announced audio of its own (a ringback tone or an announcement) before the
answer. Whenever nothing audible arrives, the SDK plays a ringback tone itself, see [Tones](#8-tones).

A call that is not answered within 90 seconds of being placed is ended by the SDK (`callDidFailToConnect`, code `timeout`).

After `callDidFailToConnect`, `await call.endReason` tells why in general terms (`.busy`, `.noAnswer`, `.rejected`,
`.failed`) and `error` has the details.

A `Call` has two identifiers. `call.callID` is the platform's call id, the one inside the token: log it and quote it
when you contact support. `call.uuid` is the same call as a `UUID`, for CallKit: the SDK makes it from the call id,
and `VoiceClient.callUUID(for: token)` gives it before the call exists. It never leaves the device. One token
always gives the same UUID, which is one more reason to get a new token for every attempt.

## 5. CallKit

With CallKit the call appears in the system: on the lock screen, in Recents, with the system's handling of
interruptions and Bluetooth buttons. This is the recommended integration.

Two rules shape the code:

1. **The call starts inside `CXStartCallAction`.** CallKit wants the call's UUID when you ask it to start a call,
   so the order is: get the token, ask the SDK for its UUID (`VoiceClient.callUUID(for:)`), request the action with
   that UUID, and call `connect` with the same token when CallKit calls back. The same goes for ending, muting and
   holding: request a `CXAction`, perform it against the SDK in the callback. This keeps the system's call screen
   and the SDK in step.
2. **Audio belongs to CallKit.** CallKit activates the audio session; you tell the SDK when
   (`audioDevice.isEnabled`). Do not activate `AVAudioSession` yourself.

```swift
import AVFAudio
import CallKit
import Foundation
import YollaVoiceSDK

@MainActor
final class CallKitCalls: NSObject, @preconcurrency CXProviderDelegate, CallDelegate {
    private let service = VoiceService.shared
    private let provider: CXProvider
    private let controller = CXCallController()

    private var current: UUID? // the call CallKit has: from the start action until its end is reported
    private var call: Call? // set once `connect` has returned
    private var pendingToken: String? // from `startCall` to the CallKit action it requests
    private var isStarting = false // `startCall` is at work: a second one must not begin
    private var starting: CheckedContinuation<Void, Error>?
    private var endRequested = false // the user ended the call before it existed
    private var endedByCallKit = false // the end came through CXEndCallAction
    private var isMuted = false
    private var wasConnected = false
    private var hasEnded = false // the SDK has reported the end of the call

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber]
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil) // delegate calls arrive on the main queue
    }

    // MARK: What your UI calls

    /// Returns when the call is on its way; throws what the token request or `connect` threw.
    func startCall(to number: String) async throws {
        // `current` stays set while the previous call's end tone plays: CallKit still has that call.
        guard current == nil, !isStarting else { throw VoiceError.callInProgress }
        isStarting = true
        defer { isStarting = false }
        endRequested = false
        // Ask for the microphone now: a permission prompt must not hold up the CallKit action.
        guard await AVAudioApplication.requestRecordPermission() else { throw VoiceError.microphoneDenied }
        try service.prepare()

        // The token comes first: CallKit wants the call's UUID, and the SDK makes it from the token.
        let token = try await fetchCallToken(to: number, userSession: currentUserSession())
        guard !endRequested else { throw VoiceError.cancelled } // the user gave up while the token was on its way
        let uuid = try VoiceClient.callUUID(for: token)
        pendingToken = token
        defer { pendingToken = nil }

        let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .phoneNumber, value: number))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            starting = continuation // before the request: CallKit may perform the action first
            controller.request(CXTransaction(action: action)) { error in
                guard let error else { return }
                Task { @MainActor in self.finishStart(throwing: error) }
            }
        }
    }

    func endCall() async {
        guard let current else {
            if isStarting { endRequested = true } // CallKit has no call yet: `startCall` gives up or ends it
            return
        }
        do {
            try await controller.request(CXTransaction(action: CXEndCallAction(call: current)))
        } catch {
            // CallKit refused: end the call anyway; the end is reported below.
            if let call { await call.hangup() } else { endRequested = true }
        }
    }

    func setMuted(_ muted: Bool) async throws {
        guard let current else { return }
        try await controller.request(CXTransaction(action: CXSetMutedCallAction(call: current, muted: muted)))
    }

    func setOnHold(_ onHold: Bool) async throws {
        guard let current else { return }
        try await controller.request(CXTransaction(action: CXSetHeldCallAction(call: current, onHold: onHold)))
    }

    private func finishStart(throwing error: Error? = nil) {
        guard let starting else { return }
        self.starting = nil
        if let error { starting.resume(throwing: error) } else { starting.resume() }
    }

    // MARK: CXProviderDelegate

    func provider(
        _ provider: CXProvider,
        perform action: CXStartCallAction
    ) {
        let uuid = action.callUUID
        current = uuid
        call = nil
        endedByCallKit = false
        isMuted = false
        wasConnected = false
        hasEnded = false
        Task {
            do {
                // The token `startCall` got: this action's UUID was made from it.
                guard let token = pendingToken else { throw VoiceError.invalidCallState }
                let call = try await service.client.connect(callToken: token, delegate: self)
                if current == uuid, !hasEnded { self.call = call } // a call can fail before `connect` returns it

                let update = CXCallUpdate()
                update.remoteHandle = action.handle
                update.supportsHolding = true
                update.supportsDTMF = true
                update.hasVideo = false
                provider.reportCall(with: uuid, updated: update)
                action.fulfill()
                provider.reportOutgoingCall(with: uuid, startedConnectingAt: nil)
                finishStart()

                // What the user did on the system's call screen while the call was being set up.
                if isMuted { await call.setMuted(true) }
                if endRequested { await call.hangup() }
            } catch {
                if current == uuid { current = nil }
                action.fail() // CallKit closes its call
                finishStart(throwing: error)
            }
        }
    }

    func provider(
        _ provider: CXProvider,
        perform action: CXEndCallAction
    ) {
        guard action.callUUID == current else { action.fail(); return }
        endedByCallKit = true
        Task {
            if let call { await call.hangup() } else { endRequested = true }
            action.fulfill()
        }
    }

    func provider(
        _ provider: CXProvider,
        perform action: CXSetMutedCallAction
    ) {
        guard action.callUUID == current else { action.fail(); return }
        isMuted = action.isMuted // applied after `connect` if the call does not exist yet
        Task {
            await call?.setMuted(action.isMuted)
            action.fulfill()
        }
    }

    func provider(
        _ provider: CXProvider,
        perform action: CXSetHeldCallAction
    ) {
        guard action.callUUID == current, let call else { action.fail(); return }
        Task {
            do {
                try await call.setOnHold(action.isOnHold)
                action.fulfill()
            } catch {
                action.fail()
            }
        }
    }

    // Audio flows only while CallKit keeps the audio session active.
    func provider(
        _ provider: CXProvider,
        didActivate audioSession: AVAudioSession
    ) {
        service.client.audioDevice.isEnabled = true
    }

    func provider(
        _ provider: CXProvider,
        didDeactivate audioSession: AVAudioSession
    ) {
        service.client.audioDevice.isEnabled = false
    }

    func providerDidReset(_ provider: CXProvider) {
        endedByCallKit = true // the system dropped its calls: nothing to report
        finishStart(throwing: CancellationError())
        Task { await service.client.disconnect() }
    }

    // MARK: CallDelegate

    func callDidConnect(_ call: Call) {
        wasConnected = true
        provider.reportOutgoingCall(with: call.uuid, connectedAt: nil)
    }

    func callDidFailToConnect(
        _ call: Call,
        error: VoiceError
    ) {
        Task {
            let reason = await call.endReason
            await finish(call, reason: reason, reporting: reason == .noAnswer ? .unanswered : .failed)
        }
    }

    func callDidDisconnect(
        _ call: Call,
        reason: Call.EndReason,
        error: VoiceError?
    ) {
        let reported: CXCallEndedReason?
        switch reason {
        case .localHangup, .cancelled:
            // Ended through CXEndCallAction: CallKit already knows. Otherwise it must be told.
            reported = endedByCallKit ? nil : .remoteEnded
        case .remoteHangup:
            reported = .remoteEnded
        default:
            reported = .failed
        }
        Task { await finish(call, reason: reason, reporting: reported) }
    }

    private func finish(
        _ ended: Call,
        reason: Call.EndReason?,
        reporting reported: CXCallEndedReason?
    ) async {
        guard ended.uuid == current, !hasEnded else { return }
        hasEnded = true
        call = nil // the call keeps its delegate: let go of it
        if let reported {
            // CallKit deactivates audio as soon as the call is reported ended: let the SDK's tone play first.
            try? await Task.sleep(for: endToneDuration(reason: reason, wasConnected: wasConnected))
            provider.reportCall(with: ended.uuid, endedAt: nil, reason: reported)
        }
        // Only now is CallKit free for the next call: it would refuse a start request while it has this one.
        if current == ended.uuid { current = nil }
    }

    func callDidStartRinging(
        _ call: Call,
        earlyMedia: Bool
    ) {}
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

Points that are easy to miss:

- **Create `CallKitCalls` once**, at app start, and keep it. An app has one `CXProvider`.
- **Ask for the microphone before the CallKit action.** `connect` asks by itself, but a permission prompt in the
  middle of `CXStartCallAction` keeps the action waiting, and CallKit does not wait long.
- **The user can act before the call exists.** Setting the call up takes a moment, and the system's End and Mute
  buttons work during it. `endRequested` and `isMuted` carry those taps over to the call.
  Hold is refused until the call exists.
- **Report every end that CallKit did not ask for.** If the other side hangs up or the call fails and you do not
  call `reportCall(with:endedAt:reason:)`, the system keeps showing a call. Ends that came through `CXEndCallAction`
  are not reported: fulfilling the action already told CallKit.
- **Let the tone play.** CallKit deactivates audio the moment a call is reported ended, which cuts the SDK's busy or
  end tone. `endToneDuration` (below) gives the time to wait: half a second after a normal call, three seconds for
  busy. A call the user ends from the system screen gets no tone: CallKit takes the audio away at once.
- **One call at a time, to the end.** CallKit has the call until its end is reported, that is until the tone has
  played; `startCall` throws `callInProgress` until then, and while an earlier `startCall` is still at work.
- **Let go of the `Call`** when it ends (`call = nil`), see [Placing a call](#4-placing-a-call).
- **`@preconcurrency CXProviderDelegate`** lets a `@MainActor` class implement the delegate. It is safe here because
  the provider was given the main queue (`queue: nil`).
- To show a name in the system's call screen, set `localizedCallerName` in the `CXCallUpdate`.

The helper both classes of this guide use:

```swift
/// How long the SDK's tone for the end of a call lasts (see Tones), with a small margin; zero when it plays none.
func endToneDuration(
    reason: Call.EndReason?,
    wasConnected: Bool
) -> Duration {
    if wasConnected { return .milliseconds(600) } // the end tone
    switch reason {
    case .busy: return .milliseconds(3100)
    case .noAnswer: return .milliseconds(900)
    case .failed, .rejected: return .milliseconds(2100) // the reorder tone
    default: return .zero
    }
}
```

## 6. Without CallKit

If the app must not show the system call UI, it owns the audio session: activate it and enable the SDK's audio
before `connect`, undo both when the call is over and its end tone has played (`endToneDuration` is in the
[CallKit](#5-callkit) section).

```swift
import AVFAudio
import Foundation
import YollaVoiceSDK

@MainActor
final class CallController: CallDelegate {
    private let service = VoiceService.shared
    private(set) var call: Call?
    private var isStarting = false
    private var current: UUID? // the call being set up or running
    private var hangupRequested = false // the user hung up before `connect` returned
    private var wasConnected = false
    private var audioRelease: Task<Void, Never>? // lets the audio go once the last call's end tone has played

    func start(to number: String) async throws {
        guard !isStarting, current == nil else { throw VoiceError.callInProgress }
        isStarting = true
        defer { isStarting = false }
        audioRelease?.cancel() // this call takes the audio session over
        hangupRequested = false
        wasConnected = false
        do {
            try service.prepare()
            let token = try await fetchCallToken(to: number, userSession: currentUserSession())
            guard !hangupRequested else { throw VoiceError.cancelled } // the user gave up meanwhile
            let uuid = try VoiceClient.callUUID(for: token) // the UUID the call will have
            current = uuid

            // Without CallKit the audio session is yours: activate it and let the SDK use it.
            try AVAudioSession.sharedInstance().setActive(true)
            service.client.audioDevice.isEnabled = true

            let call = try await service.client.connect(callToken: token, delegate: self)
            if current == uuid { self.call = call } // otherwise the call has already ended
            if hangupRequested { await call.hangup() }
        } catch {
            current = nil
            releaseAudio()
            throw error
        }
    }

    func hangup() async {
        if let call { await call.hangup() } else { hangupRequested = true }
    }

    private func releaseAudio() {
        service.client.audioDevice.isEnabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func finish(
        _ ended: Call,
        reason: Call.EndReason?
    ) {
        guard ended.uuid == current else { return }
        current = nil
        call = nil // the call keeps its delegate: let go of it
        // Keep the session until the SDK's end tone has played, unless the next call has started by then.
        let tone = endToneDuration(reason: reason, wasConnected: wasConnected)
        audioRelease = Task {
            try? await Task.sleep(for: tone)
            if !Task.isCancelled { releaseAudio() }
        }
    }

    // MARK: CallDelegate

    func callDidStartRinging(
        _ call: Call,
        earlyMedia: Bool
    ) { /* show "Ringing…" */  }
    func callDidConnect(_ call: Call) { wasConnected = true /* start the call timer */ }
    func callIsReconnecting(
        _ call: Call,
        error: VoiceError
    ) { /* show "Reconnecting…" */  }
    func callDidReconnect(_ call: Call) { /* back to the call screen */  }
    func callDidReceiveQualityWarnings(
        _ call: Call,
        current: Set<CallQualityWarning>,
        previous: Set<CallQualityWarning>
    ) {}

    func callDidFailToConnect(
        _ call: Call,
        error: VoiceError
    ) {
        // The call never connected: busy, no answer, rejected, network.
        Task { finish(call, reason: await call.endReason) }
    }

    func callDidDisconnect(
        _ call: Call,
        reason: Call.EndReason,
        error: VoiceError?
    ) {
        finish(call, reason: reason)
    }
}
```

On this path the app handles what CallKit would: an incoming phone call or an alarm interrupts the audio session
(`AVAudioSession.interruptionNotification`), and nothing but your own UI shows that a call is running.

## 7. During a call

```swift
await call.setMuted(true) // local, immediate
try await call.setOnHold(true) // signalled to the other side; can throw
try await call.sendDigits("1234#") // DTMF: 0-9, *, #, A-D
await call.hangup()
```

- **Mute** silences the microphone locally. It cannot fail.
- **Hold** is agreed with the other side, takes a moment and can throw (`invalid_call_state` when the call is not
  connected). The microphone is silent while the call is on hold.
- **DTMF** works on a connected call; `dtmf_unavailable` means this call cannot carry digits.
- **Hang up** ends the call in any state. Before the answer it cancels the attempt.
- `call.state`, `call.isMuted`, `call.isOnHold` and `call.endReason` read the current values (`await`).
- With CallKit, do not call `setMuted`, `setOnHold` and `hangup` from your UI directly: request the `CXAction`, as
  in [CallKit](#5-callkit).

**Audio route.** Speaker, receiver and Bluetooth are the system's business: show an `AVRoutePickerView`, as the
example app does in `AudioRouteButton.swift`.

### Reconnection

When the device changes network (Wi-Fi to cellular, a tunnel, a lift) the SDK restores the call by itself:

1. `callIsReconnecting(_:error:)`; the error's `code` says what was noticed (`network_changed`, `ice_failed`,
   `signaling_reconnected`). The SDK plays a quiet tick while it tries.
2. `callDidReconnect(_:)` when audio is back, or
3. `callDidDisconnect` with the reason `.failed` and the error `media_timeout` if the call could not be restored.
   The SDK tries for 20 seconds at most.

The app has nothing to do except show the state.

### Quality

```swift
let stats = await call.stats()
print(stats.sample.mos ?? 0, stats.sample.lossPercent ?? 0, stats.media.codec ?? "-")
```

`stats.sample` is the last second of the call: round-trip time, jitter, packet loss, and an estimated MOS (1 to 4.5,
higher is better). `stats.media` holds the counters since the call started, the codec, and how the audio travels
(`candidateType`: `host`, `srflx`, `relay`). The values are refreshed once a second and are empty until the call is
answered.

`callDidReceiveQualityWarnings(_:current:previous:)` is called when the set of warnings changes:

| Warning | Raised when | Meaning |
|---|---|---|
| `high_rtt` | round trip of 400 ms or more | Long delay between the sides |
| `high_jitter` | jitter of 30 ms or more | Audio packets arrive unevenly |
| `high_packet_loss` | loss of 3 % or more | Audio packets are being lost |
| `low_mos` | MOS below 3.5 | The estimated quality is poor overall |

A warning is cleared after two good seconds in a row, so the set does not flicker. A typical use is a
"Poor connection" label while the set is not empty.

## 8. Tones

The SDK synthesizes the sounds a caller expects, so the app ships no audio files and configures nothing:

| Tone | When it plays | Length |
|---|---|---|
| Ringback | While the other side rings and the network sends no audio of its own. The cadence follows the dialled number: North American for `+1`, British for `+44`, European otherwise. | until the answer |
| Busy | The other side is busy | 3 s |
| No answer | The other side did not answer | 0.8 s |
| Reorder (fast busy) | The call failed or was rejected before the answer | 2 s |
| Ended | A connected call ended | 0.5 s |
| Reconnecting | A quiet tick while the call is being restored | until the call is back |

The tones that follow the end of a call need the audio session to stay active while they play: that is what
`endToneDuration` in the [CallKit](#5-callkit) section is for.

## 9. Errors

Everything the SDK throws or reports is a `VoiceError`:

```swift
public struct VoiceError: Error {
    public var code: String        // stable, for your code
    public var message: String     // English, for your logs
    public var sipStatus: Int?     // set when the network refused the call
}
```

Switch on `code`. `message` is for logs and support, not for users.

```swift
@MainActor
func message(for error: Error) -> String {
    guard let error = error as? VoiceError else { return error.localizedDescription }
    switch error.code {
    case "microphone_denied": return "Allow microphone access in Settings to make calls."
    case "call_in_progress": return "Another call is active."
    case "invalid_token": return "The call could not be authorised. Try again."
    case "network_error", "timeout", "connection_lost": return "No connection. Check the network and try again."
    default: return "The call failed (\(error.code))."
    }
}
```

### Codes

| Code | Where | Meaning and what to do |
|---|---|---|
| `invalid_token` | `connect`, `callDidFailToConnect`; rarely `setOnHold`, `callDidDisconnect` | The token is not a call token, has expired or was already used. Get a new token from your backend. |
| `microphone_denied` | `connect` | The user refused the microphone. Send them to the app's page in Settings. |
| `call_in_progress` | `connect` | This client already has a call. |
| `network_error` | `connect` | The platform could not be reached. Offer to retry. |
| `http_<status>` | `connect` | The platform answered with an HTTP error, for example `http_503`. |
| `protocol_error`, `redirected` | `connect`, call end | An unexpected answer. Report it to support. |
| `timeout` | `connect`, `callDidFailToConnect`, `callDidDisconnect` | No answer from the network in time, or the call was not answered within 90 seconds. |
| `connection_lost` | `connect`, call end | The connection dropped while the call was being set up or ended. |
| `media_failed` | `connect`, call end | Audio could not be set up. |
| `sip_<status>` | `callDidFailToConnect`; also `connect`, `setOnHold`, `callDidDisconnect` | The network refused the call or the operation; `sipStatus` has the number (`sip_486` busy, `sip_480` not available, `sip_403` not allowed, `sip_404` no such number). `message` carries the network's explanation when there is one. |
| `failed` | `callDidFailToConnect` | The call ended before the answer without a reason given. |
| other codes | `connect`, `callDidFailToConnect` | The platform can refuse a call with a code of its own (for example for an account without credit). Treat any unknown code as "the call failed" and log `code` and `message`. |
| `media_timeout` | `callDidDisconnect` | Reconnection did not succeed (it is tried for 20 seconds at most). |
| `network_changed`, `ice_failed`, `signaling_reconnected` | `callIsReconnecting` | Why a reconnection started. Informational. |
| `invalid_call_state` | `setOnHold`, `sendDigits` | The call is not connected. |
| `dtmf_unavailable` | `sendDigits` | This call cannot carry DTMF. |
| `cancelled` | `connect` | The set-up was cancelled: `disconnect()` was called, or the task that called `connect` was cancelled (that can also surface as Swift's `CancellationError`). |

### End reasons

`Call.EndReason`, in `callDidDisconnect` and in `call.endReason`:

| Reason | Meaning |
|---|---|
| `.localHangup` | You hung up a connected call |
| `.cancelled` | You hung up before the answer |
| `.remoteHangup` | The other side hung up |
| `.busy` | The other side is busy |
| `.noAnswer` | The network reported no answer, or not available |
| `.rejected` | The other side declined |
| `.failed` | Anything else; see the error |

The SDK is a binary framework that can gain cases in a later version: a `switch` over `Call.EndReason`,
`Call.State` or `CallQualityWarning` needs an `@unknown default`.

## 10. Troubleshooting

**The call connects but there is no sound.** The SDK's audio is off until `audioDevice.isEnabled` is `true`. With
CallKit, check that `provider(_:didActivate:)` is reached and sets it: it is not called if the call was started
without a `CXStartCallAction`. Without CallKit, check that the session was activated before `connect`. Also check
that `audioDevice.configure()` ran.

**The app is terminated on the first call.** `NSMicrophoneUsageDescription` is missing.

**The call drops when the app goes to the background.** The `audio` background mode is missing.

**`invalid_token` on every call.** The token is requested too early or used twice, or the backend returns something
that is not the platform's call token. Ask for a token at the moment of the call and pass it on unchanged.

**The system keeps showing a call after it ended.** An end was not reported to CallKit: see the list after the code
in [CallKit](#5-callkit).

**The end or busy tone is cut off.** The audio session was deactivated, or the end reported to CallKit, before the
tone finished. Wait for `endToneDuration`, as the classes of this guide do.

**No audio on the simulator.** The simulator is fine for the interface and for call setup; test audio on a device.

### Reporting a problem

The SDK keeps its own diagnostic log and, when Yolla support turns that on for your account, sends it to the
platform after a call. There is nothing to configure in the app. Give support:

- `call.callID` of the call, and when it was made;
- `VoiceSDK.version`, the iOS version and the device model;
- the `code` and `message` of the error, if there was one.
