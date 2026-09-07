# Troubleshooting

## I downloaded “Source code” and can’t find the app

On [Releases](https://github.com/jmania/span/releases), expand **Assets** and choose **Span-macOS.dmg**. If no signed release is listed, the public installer is still being prepared.

## The event app is unavailable on my Mac

The current workflow needs an Apple-silicon Mac (M1 or newer). Look in the Mac App Store’s iPhone & iPad apps section. Event access and availability are controlled by the event provider.

## Span keeps asking for attendee access

Open **System Settings → Privacy & Security → Accessibility**, then enable Span. Open the same copy you authorized, preferably the one in Applications.

Development previews may lose permission after being rebuilt. Quit Span, remove only its old entry with the minus button, add the current Span app with the plus button, enable it, and reopen it. Your saved inputs are unaffected.

## Collection stays at zero initially

Read the progress message: Span returns to the beginning before counting. Starting at the end of a long list takes several minutes. Leave the event app on All attendees.

## Collection stops or reports an incomplete count

Make sure the event app is signed in, shows All attendees, and has no search or filter applied. Wait until names load, then try **Collect attendees again**. Avoid interacting with the event app during the scan. Saved inputs are retained if collection fails.

For a bug report, include the Span version, macOS version, expected count, observed count, and exact error. `~/Library/Application Support/Summit Network/scan-diagnostics.txt` contains counts and scroll actions, without attendee names.

## My connections archive hasn’t arrived

LinkedIn prepares the file. Larger archives can take up to 24 hours; some arrive sooner. You can collect attendees and browse the directory while waiting.

## No matches, or a match looks wrong

The list works without an archive. For suggestions, confirm the archive contains Connections. People may use different names or have changed jobs. Expand a suggested row and choose Different person to reject a wrong pairing; the attendee remains. Confirmed by you starts empty until you check identities. Use Refresh order after decisions to update the current filter.

## Report a problem

[Open an issue](https://github.com/jmania/span/issues/new?template=bug_report.yml). Do not attach your LinkedIn archive, attendee export, private messages, or contact details. A description and the non-personal diagnostic log are usually sufficient.
