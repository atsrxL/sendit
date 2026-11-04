# SendIt

<img src="altstore/icon.png" width="96" align="right" alt="SendIt icon">

SendIt is an iOS / iPadOS share extension that sends files straight to your NAS: in any app, tap **Share → 发送到 NAS**, then pick a folder.

- **SMB** (SMB2/3, via [AMSMB2](https://github.com/amosavian/AMSMB2)) and **WebDAV** (HTTP/HTTPS, Basic/Digest auth)
- Each server can have **several destination folders**, and you pick one when you share
- Accepts photos, videos, files, links (saved as `.url`) and text (saved as `.txt`)
- Creates missing folders and renames on clashes (`name (1).jpg`)
- Remembers the folder you used last
- You can also pick files from the Files app inside the main app and send them

## Install

### AltStore / SideStore source

```
https://raw.githubusercontent.com/atsrxl/sendit/main/altstore/source.json
```

### Sign it yourself

Download `SendIt.ipa` from [Releases](https://github.com/atsrxl/sendit/releases). It is **unsigned** (ad-hoc signed only, so the entitlements are embedded). Sign it with your own certificate (AltStore, SideStore, Sideloadly, ESign, `zsign`, …).

> **Important:** the app and the share extension share their settings through an **App Group**. Keep the `com.apple.security.application-groups` entitlement when you sign. SendIt reads the group ID from the provisioning profile at runtime, so it still works when the signing tool renames the group (for example by appending a team ID). If the main app shows "App Group 不可用", the group was lost during signing.

| | Bundle ID |
|---|---|
| App | `com.atsrxl.sendit` |
| Share extension | `com.atsrxl.sendit.share` |
| App Group | `group.com.atsrxl.sendit` |

## Usage

1. Open SendIt and tap **+** to add a server.
   - WebDAV: enter the root URL, e.g. `http://192.168.1.10:5005/dav`
   - SMB: enter the host, share name, username and password (tap **测试连接** to list the shares)
2. Under **目的目录**, add one or more folders. You can type a path or browse the server.
3. In any app, tap Share → **发送到 NAS** and choose a folder.

> If **发送到 NAS** isn't in the share sheet, scroll to the end of the app row, tap **更多** and turn it on.

## Build

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
scripts/build_ipa.sh        # → dist/SendIt.ipa
```

Publishing a GitHub Release triggers [`.github/workflows/release.yml`](.github/workflows/release.yml), which builds the IPA, uploads it to the Release and updates `altstore/source.json`.

## Project layout

```
App/             Main app: server and folder settings, upload from Files
ShareExtension/  Share extension entry point and share-item parsing
Shared/          Models, config storage (App Group), WebDAV/SMB clients, upload UI
altstore/        AltStore source and icon
scripts/         IPA packaging, source updater, icon generator
```

## Notes

- Passwords are stored in plain JSON inside the App Group container (file protection: until first unlock). They are not in the Keychain, because sideload re-signing often breaks Keychain sharing.
- A share extension can only run while it is on screen. Keep the sheet open until a large upload finishes.

## License

MIT. AMSMB2 / libsmb2 are LGPL-2.1 and are linked as a dynamic framework.
