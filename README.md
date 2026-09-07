# Summit Network

Summit Network is a privacy-first Mac tool for answering a useful conference question: **which attendees are already close to my professional network?**

It does three things:

1. Reads the visible attendee directory from the running iPhone/iPad event app using macOS Accessibility.
2. Matches those attendees locally against your own LinkedIn `Connections.csv` export (first-degree connections).
3. Opens a private, local review queue for checking the remaining people as second-degree or not connected using LinkedIn's normal search interface.

The project never asks for a LinkedIn password, copies browser cookies, scrapes LinkedIn pages, or uploads the attendee list. All CSV files and review decisions stay on your Mac.

## Why the LinkedIn step is user-controlled

LinkedIn's User Agreement prohibits browser plug-ins, scripts, bots, and other software that scrape or automate its service. LinkedIn also says those tools can result in account restriction. Its supported data download includes names, public profile URLs, companies, and positions for your first-degree connections, but not second-degree connections.

For that reason, Summit Network automates the safe part—first-degree matching from your own export—and makes second-degree checking fast and resumable without reading or controlling LinkedIn.

Official references:

- [LinkedIn User Agreement](https://www.linkedin.com/legal/user-agreement)
- [Prohibited software and extensions](https://www.linkedin.com/help/linkedin/answer/a1341387)
- [Download your account data](https://www.linkedin.com/help/linkedin/answer/a1339364)

## Requirements

- An Apple-silicon Mac capable of running the event's iOS app
- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`); the launcher builds the small native exporter on first use
- Python 3.10 or later (included with many developer setups)
- Your own lawful access to the event directory and LinkedIn account

No Python packages, browser extension, API key, or account credentials are required.

## Quick start

Clone the repository, then from its directory:

```sh
chmod +x bin/summit-network
```

### 1. Export attendees

Open the event app and navigate to **Attendees → All attendees**. Leave that screen visible, then run:

```sh
./bin/summit-network extract --output attendees.csv
```

On the first run, macOS will ask for Accessibility access. Enable the terminal you are using in **System Settings → Privacy & Security → Accessibility**, return to the attendee screen, and run the command again.

The exporter scrolls the attendee list, deduplicates names, and writes `name`, `details`, and the original accessibility label to CSV. Keep the window open until it finishes. Verify the final count against the count shown in the app.

For a different event app, supply its bundle identifier:

```sh
./bin/summit-network extract --bundle-id com.example.event --output attendees.csv
```

### 2. Download your first-degree connections

In LinkedIn, go to **Settings & Privacy → Data privacy → Get a copy of your data** and request the archive that includes connections. When LinkedIn provides the archive, locate `Connections.csv`.

Do not place this file in a public repository. The included `.gitignore` excludes common export filenames.

### 3. Match first-degree connections

```sh
./bin/summit-network match attendees.csv /path/to/Connections.csv --output network-results.csv
```

Matching is intentionally conservative:

- Exact normalized names are accepted.
- Duplicate names require supporting company/title overlap.
- Fuzzy names are accepted only at a high threshold, with details used where available.
- Everything uncertain remains `review`.

The output includes the connection degree, confidence, public profile URL when present in your export, and the reason for each decision.

### 4. Review second-degree candidates

```sh
./bin/summit-network review network-results.csv
```

A page opens on `127.0.0.1` (your Mac only). For each unmatched attendee:

1. Copy the prepared name/company search text.
2. Open LinkedIn and paste it into LinkedIn's search.
3. Mark the attendee **2nd degree**, **Not connected**, **Skip**, or correct them to **1st**.

Each decision is saved immediately back to `network-results.csv`, so you can stop and resume at any time.

## Output schema

| Column | Meaning |
|---|---|
| `name` | Attendee name from the event app |
| `details` | Company/title text exposed by the app |
| `degree` | `1st`, `2nd`, `not_connected`, `review`, or `skip` |
| `confidence` | Local first-degree match score |
| `linkedin_url` | URL supplied by your LinkedIn export, if matched |
| `matched_connection` | Name in your connections export |
| `match_reason` | Why the matcher accepted or withheld a match |
| `reviewed_at` | Timestamp for a manual review decision |

## Privacy and responsible use

- Only process attendee data you are authorized to access.
- Keep raw attendee and connection exports private.
- Do not use the results for spam or bulk outreach.
- Do not publish attendee data, results, passwords, cookies, or account archives.
- Respect the event's rules, attendee expectations, privacy law, and LinkedIn's terms.

This project is not affiliated with or endorsed by Lenny's Newsletter, Zuddl, or LinkedIn. Event and product names belong to their respective owners.

## Development

Run the tests:

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
swift test
```

The Python portion uses only the standard library. The Swift exporter uses Apple's public Accessibility APIs and does not inspect app files, network traffic, or private storage.

## Known limitations

- Accessibility labels vary between event app versions; inspect the output before relying on it.
- Attendees with identical names and no company/title must be reviewed manually.
- The event app must remain open on the attendee list while exporting.
- Second-degree classification is intentionally human-in-the-loop because LinkedIn does not provide it in the member data export or generally available Connections API.

Contributions that improve accessibility-label parsing, matching quality, or support additional event apps are welcome—without adding LinkedIn scraping or browser automation.
