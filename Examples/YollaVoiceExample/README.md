# Yolla Voice example app

A complete SwiftUI app that places phone calls with the Yolla Voice SDK. It is the reference integration: the code
is meant to be read and copied.

What it shows:

- a dialer and an in-call screen with a timer, mute, hold and a DTMF keypad;
- CallKit: the system call screen, the lock screen, Recents;
- the same call without CallKit (a switch in Settings);
- speaker, receiver and Bluetooth through the system route picker;
- reconnection when the network changes, quality warnings and live call statistics;
- a log of the app's own events with export.

## Requirements

Xcode 26 or later, iOS 17 or later. A real iPhone to hear a call: the simulator is fine for the interface and for
call setup, but not for audio.

## Run

1. Open `YollaVoiceExample.xcodeproj`. The project takes the SDK from this repository (the package two folders up),
   so there is nothing to install.
2. Set up signing. Create the file `Config/Signing.local.xcconfig` with one line:

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   ```

   with your team ID. The file is git-ignored. Or choose the team in Xcode under **Signing & Capabilities**.
3. Set the demo token. Create the file `Config/Local.xcconfig` with one line:

   ```
   YOLLA_VOICE_DEMO_TOKEN = <your demo token>
   ```

   with the token Yolla gave you for its demo backend. The file is git-ignored too. Without it the app tells you
   that the token is not set when you call; a pasted call token (see below) works without it.
4. Run the app on your iPhone.
5. Open **Settings** in the app and check the token source (see below).
6. Open **Dialer**, enter a number and tap **Call**. The number goes to the backend as typed. On the first call
   iOS asks for the microphone.

## Where the token comes from

Every call needs a call token from a backend; the guide explains
[why](../../Documentation/Integration.md#3-the-call-token). The app has two sources, chosen in **Settings**:

- **Token URL.** Before each call the app sends a request to this address and expects a token back:

  ```
  POST <Token URL>
  Authorization: Bearer <YOLLA_VOICE_DEMO_TOKEN>
  Content-Type: application/json

  {"to": "+4915112345678"}
  ```

  ```
  200 OK

  {"callToken": "<jwt>"}
  ```

  The default address is Yolla's demo backend, and the demo token is the credential it expects. The token is not in
  the code: it is the build setting `YOLLA_VOICE_DEMO_TOKEN`, which `Config/Example.xcconfig` sets to a placeholder
  and your `Config/Local.xcconfig` to the real value; the app reads it from its Info.plist
  (`TokenProvider.demoToken`). To use your own backend, change the address in Settings and put its credential in
  the same build setting. In your own app this request is authorised with your user's session, not with a value
  built into the app.
- **Pasted token.** Paste a call token you got some other way. The call goes to the number inside the token,
  whatever you dial, and a token works for one call.

## How the app is built

| File | What it shows | In the guide |
|---|---|---|
| `App/AppModel.swift` | Creating the one `VoiceClient`; starting a call with CallKit and without: token first, then the call's UUID, then CallKit; turning errors into messages | [The client](../../Documentation/Integration.md#2-the-client), [Without CallKit](../../Documentation/Integration.md#6-without-callkit) |
| `Auth/TokenProvider.swift` | The token request to the backend | [The call token](../../Documentation/Integration.md#3-the-call-token) |
| `CallKit/CallKitManager.swift` | `CXProvider` and its delegate: start, end, mute and hold as CallKit actions; audio activation passed to the SDK | [CallKit](../../Documentation/Integration.md#5-callkit) |
| `Call/CallViewModel.swift` | `CallDelegate`: call events turned into screen state and CallKit reports; polling statistics | [Placing a call](../../Documentation/Integration.md#4-placing-a-call), [During a call](../../Documentation/Integration.md#7-during-a-call) |
| `Call/InCallView.swift`, `Call/DTMFKeypadView.swift` | The call screen: mute, hold, digits, quality | [During a call](../../Documentation/Integration.md#7-during-a-call) |
| `Call/AudioRouteButton.swift` | The system audio route picker in SwiftUI | [During a call](../../Documentation/Integration.md#7-during-a-call) |
| `Settings/` | The app's two settings and their storage | |
| `History/` | The calls placed from the app, kept in UserDefaults; a tap calls the number again | |
| `Logs/` | The app's event log. The SDK's own log is not available to an app | [Troubleshooting](../../Documentation/Integration.md#10-troubleshooting) |

The unit tests in `YollaVoiceExampleTests` cover the CallKit flow, the mapping of call states and the token request,
with fakes in place of the SDK and CallKit.

## Using the code in your app

- **Concurrency settings.** The app target uses Xcode 26 defaults: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and
  approachable concurrency. The models, the token provider and the view models state their isolation explicitly;
  the SwiftUI views and helpers rely on the default. If the compiler complains about isolation in a copied file,
  this setting is why.
- **CallKit actions.** With CallKit on, End, Mute and Hold are requested as `CXAction`s and carried out in
  `CallKitManager`'s `perform` handlers, so the system call screen and the SDK stay in step. Without CallKit the
  view model calls the SDK directly.
- **The end tone.** `CallViewModel` holds the CallKit end report, and `InCallView` the release of the audio
  session, until the SDK's busy or end tone has played (`CallViewModel.endToneDuration`); either one sooner cuts
  the tone. The guide's [CallKit section](../../Documentation/Integration.md#5-callkit) explains it.
- **Storage.** Settings, including a pasted token, are in `UserDefaults` to keep the example short. Keep anything
  secret in the Keychain.
- **The log.** The exported app log contains phone numbers; treat it as personal data.

## License

The example app is under the [MIT License](LICENSE). The SDK it uses is proprietary; see the
[LICENSE](../../LICENSE) in the repository root.
