# Small World

<img src="Assets/SmallWorld-Icon.png" width="144" alt="Two hands cradling a small globe" />

**You know more people here than you think.**

Made by [Josh Jacobson](https://www.linkedin.com/in/josh--jacobson/) for fellow Lenny & Friends attendees.

I wanted to know which familiar faces were hiding in a long conference attendee list. Small World is my answer: a free, open-source Mac app that helps you find people you know and prepare for a few new conversations.

It collects the attendee names visible in the event app, matches them locally against your own LinkedIn connections export, and gives you a simple review queue for everyone else. It never asks for a LinkedIn password, reads browser cookies, scrapes LinkedIn, uploads attendee data, or sends messages.

## Install the Mac app

**Preview status:** the native app and sample review flow are working. Full-directory collection still needs a live verification run, and an Apple-notarized public download has not been published yet. Source is available now; the installation steps below describe the planned signed release.

No Terminal, Python, Xcode, browser extension, or API key is required.

1. Open this repository’s **Releases** page.
2. Download `Small-World-0.3.0.dmg`.
3. Open it and drag **Small World** into Applications.
4. Open Small World and follow the instructions in the window.

Official releases should be signed and notarized so macOS can verify the developer. If you build the app from source yourself, that local build is ad-hoc signed and macOS may identify it as an unnotarized development build.

## Use the app

### 1. Prepare the event app

Install and sign in to Lenny & Friends on an Apple-silicon Mac. Open **Attendees → All attendees** and leave that screen visible.

In Small World:

1. Click **Allow attendee access**.
2. Enable Small World in **System Settings → Privacy & Security → Accessibility** if macOS asks.
3. Return to Small World and click **Check again**.
4. Click **Collect attendees**.

The app shows a live count while it reads the directory. Keep Lenny & Friends open until collection finishes. The collected list and review decisions are stored privately in Application Support on your Mac; partial collection is not yet saved if extraction is interrupted.

You can click **Preview with sample data** before granting access if you want to see the results workflow first. Sample data is fictional and is not saved.

### 2. Get your LinkedIn connections archive

In LinkedIn, open **Settings & Privacy → Data privacy → Get a copy of your data** and request the archive that includes connections. LinkedIn will provide a ZIP download.

Drag that ZIP directly into Small World. You do not need to unzip it or locate `Connections.csv`; the app does that for you.

### 3. Review the results

First-degree connections are matched automatically. For each remaining attendee, Small World prepares name-and-company search text:

1. Click **Copy search text**.
2. Click **Open LinkedIn** and paste the text into LinkedIn’s normal search.
3. Mark the attendee **Second degree**, **Not connected**, **Actually first**, or **Skip for now**.

Every real review decision is saved immediately. You can quit and resume later. When finished, click **Export spreadsheet…** to save the results as CSV.

## One more connection?

I’m Josh. I built this to make meeting people at the summit a little easier. If it helps, [add me on LinkedIn](https://www.linkedin.com/in/josh--jacobson/) and come say hello. I promise I’m easier to find than the export button.

The invitation in the app is optional and dismissible. It opens my profile; it never sends a request or changes your matches.

## Why second-degree review is user-controlled

LinkedIn’s User Agreement prohibits browser plug-ins, scripts, bots, and other software that scrape or automate its service. LinkedIn also warns that prohibited tools can result in account restrictions. Its supported account download includes first-degree connections but not second-degree connections.

Small World therefore automates the supported first-degree comparison and makes second-degree review fast and resumable without reading or controlling LinkedIn.

Official references:

- [LinkedIn User Agreement](https://www.linkedin.com/legal/user-agreement)
- [Prohibited software and extensions](https://www.linkedin.com/help/linkedin/answer/a1341387)
- [Download your account data](https://www.linkedin.com/help/linkedin/answer/a1339364)

## Privacy

- Attendee and connection data stays on the user’s Mac.
- The app has no analytics, cloud service, or advertising SDK.
- It does not contain a LinkedIn login form.
- It does not inspect LinkedIn pages or automate browser activity.
- Private CSV files and saved review data are excluded from Git by default.
- **Start over** explains exactly what will be removed and asks for confirmation.

Only process directories you are authorized to access. Do not publish attendee data or use results for spam or bulk outreach. Respect the event’s rules, attendee expectations, privacy law, and LinkedIn’s terms.

This project is not affiliated with or endorsed by Lenny’s Newsletter, Zuddl, or LinkedIn. Event and product names belong to their respective owners.

## Build from source

Developers need macOS 13 or later, Xcode Command Line Tools, Swift 6, and Python 3 for the test suite and icon packager.

Build a universal application and local release archive:

```sh
./scripts/build_app.sh
```

The script builds both Apple-silicon and Intel binaries, creates `Small World.app`, signs it locally, and packages it. On a normal Mac it produces a DMG. Environments that cannot create disk images receive a ZIP fallback.

Run tests:

```sh
swift test
python3 -m unittest discover -s Tests -p 'test_*.py' -v
```

### Signing and GitHub Releases

The release workflow builds a universal app, signs it with a Developer ID certificate, submits the DMG to Apple for notarization, staples the notarization ticket, and attaches the DMG to the GitHub release.

Repository maintainers must configure these GitHub Actions secrets:

- `MACOS_CERTIFICATE_P12` — base64-encoded Developer ID Application certificate
- `MACOS_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`

Create a tag such as `v0.3.0` to run the release workflow.

## Command-line tools

The original command-line workflow remains available for development and troubleshooting:

```sh
./bin/summit-network extract --output attendees.csv
./bin/summit-network match attendees.csv /path/to/Connections.csv --output network-results.csv
./bin/summit-network review network-results.csv
```

Run `./bin/summit-network help` for details. End users should use the Mac application instead.

## Known limitations

- The Lenny & Friends iOS app currently requires an Apple-silicon Mac.
- Accessibility labels can change between event-app versions; verify the attendee count shown after collection.
- People with identical names and insufficient company/title information require review.
- Second-degree classification is intentionally human-in-the-loop.

Contributions that improve accessibility parsing, matching quality, onboarding, or support for additional event apps are welcome—without adding LinkedIn scraping or browser automation.
