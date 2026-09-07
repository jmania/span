# Building and releasing Span

Use macOS 13 or later with Swift 6 and Xcode Command Line Tools. Collection requires the event app on an Apple-silicon Mac. Python 3 runs the legacy matching tests.

```sh
./scripts/build_app.sh
swift test
./scripts/test_app_workflow.sh
python3 -m unittest discover -s Tests -p 'test_*.py' -v
```

The build produces a universal `Span.app` and versioned DMG in `dist/`, or a ZIP when disk images are unavailable. Local builds are ad-hoc signed development previews, not notarized public releases. Rebuilding a preview can invalidate its Accessibility permission.

## Public releases

Public downloads require a Developer ID Application signing identity and Apple notarization. Versions come from `Resources/Info.plist`; the release tag must match.

The release workflow tests, builds, signs, and notarizes the app and disk image, then creates a **draft** release. It uses `Span-macOS.dmg` as the stable download name. After publication, the download URL will be `https://github.com/jmania/span/releases/latest/download/Span-macOS.dmg`.

Configure these repository secrets under GitHub Settings → Secrets and variables → Actions:

- `MACOS_CERTIFICATE_P12`: base64-encoded Developer ID Application certificate and private key exported as a password-protected P12.
- `MACOS_CERTIFICATE_PASSWORD`: the P12 password.
- `KEYCHAIN_PASSWORD`: a separate random password for the temporary CI keychain.
- `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`: Apple account, developer team ID, and app-specific password for notarization.

Enter credentials directly in the relevant interfaces. Never commit them or paste private keys or passwords into issues or chat.

Once configured, create and push a matching tag such as `v0.4.2`. Review the draft and test its downloaded build on another Mac before publishing. Update the README and setup guide’s release-status notice when the installer is available.

[Apple Developer ID](https://developer.apple.com/developer-id/) · [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## Command-line tools

```sh
./bin/summit-network extract --output attendees.csv
./bin/summit-network match attendees.csv /path/to/Connections.csv --output network-results.csv
./bin/summit-network review network-results.csv
```

Run `./bin/summit-network help` for details. End users should use the packaged Mac app.
