# Vizio Remote for iPhone (native)

A real iOS app that does what the web page does - but it can actually reach the TV.

## Why native works when the web page can't

Your V505-G9 serves its API over HTTPS with a certificate iOS can never be made to trust.
Measured from the TV:

```
subject     CN=MT5581.prod.vizio.com, O=VIZIO Inc
issuer      CN=dev.vizio.com                     <- Vizio's internal CA, never sent, not on iOS
chain sent  1 cert (leaf only)                   <- nothing for iOS to anchor to
is CA       false
SAN         (none)
```

Safari hides that behind a one-time "visit anyway" tap. A page added to the **Home Screen**
runs in a container that cannot show that prompt, so every request dies silently - that's the
hang on "connecting to https://192.168.10.128". A native app may accept the server's
certificate for the host you configured; Vizio's own app does exactly that. No LAN box, no PC,
no tunnel.

## Layout

| file | what it is |
|---|---|
| `project.yml` | XcodeGen project definition (text, so no binary `.xcodeproj` to commit) |
| `Sources/TVClient.swift` | SmartCast API client, key table, certificate handling |
| `Sources/RemoteModel.swift` | connection state, polling, actions |
| `Sources/VizioRemoteApp.swift` | app entry, settings screen, theme |
| `Sources/RemoteView.swift` | the remote UI (D-pad, volume slider, inputs) |
| `.github/workflows/ios.yml` | builds an unsigned `.ipa` on a free macOS runner |

## Build it (no Mac required)

1. Create a GitHub repo and push **this folder as the repo root**.
   Make it **public** - free macOS runner minutes only apply to public repos.
   Nothing secret is in here: the app asks for the IP and token at runtime.
2. `Actions` -> `build-ios-app` -> **Run workflow**.
3. Download the `VizioRemote-unsigned-ipa` artifact.

With a Mac: `brew install xcodegen && xcodegen generate`, open `VizioRemote.xcodeproj`, build to the phone.

## Install it (Windows PC needed once)

A free Apple ID signs apps for 7 days; SideStore re-signs on the device, so the PC is only
needed the first time.

1. Install **SideStore** (https://sidestore.io) - follow its one-time pairing guide. It wants
   iTunes and iCloud from **apple.com**, not the Microsoft Store builds.
2. In SideStore: `My Apps` -> `+` -> choose `VizioRemote-unsigned.ipa` -> sign in with your
   Apple ID -> Install.
3. On the phone: Settings -> General -> **VPN & Device Management** -> trust the developer, then
   Settings -> Privacy & Security -> **Developer Mode** -> On -> restart.
4. Open the app, enter the TV address, port `7345`, and the AUTH token -> **Save & test**.

## Notes

- Same Wi-Fi as the TV, and it needs the TV awake (SmartCast drops off when the TV sleeps -
  use the Fire TV app or a WoL app to wake it; no browser or app can send the magic packet).
- The certificate exception is scoped to the one host you configure, not to all servers.
- `NSAllowsArbitraryLoads` is enabled so you can also point it at the optional PC bridge
  over plain HTTP while testing.
- Layout mirrors the web version, including the safe-area spacing, so nothing hides under the
  status bar.
