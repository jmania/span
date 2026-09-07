# Privacy and limitations

Span reads the attendee directory you can access in the event app and compares it with the connections export you choose. Processing and saved inputs stay on your Mac. There is no cloud account, analytics service, or advertising SDK.

Accessibility lets Span read and scroll the event app. Span does not send messages or connection requests. LinkedIn searches open in your browser, where LinkedIn receives the search terms and handles your browser session. Span does not read LinkedIn pages, passwords, or cookies.

Inputs and decisions are stored in `~/Library/Application Support/Summit Network/session-v2.json`. **Start over** asks before deleting that session. It does not delete the original archive. Diagnostic logs in the same folder record counts and scroll actions without attendee names.

## What results mean

- Possible connections use name similarity and meaningful company words. They are leads, never automatic confirmations. Confirmations are explicitly made by the user; a dismissed pairing is not a claim of non-connection.
- Second-degree labels are manually recorded; the connections export does not supply them.
- Span reads list-card information, not every profile-detail page. It uses LinkedIn links from matches in your archive where available and offers a pre-filled search otherwise.
- Event app changes can affect collection. Span rejects incomplete scans when the count differs from the event app’s total. Counts can change as people join the event.

The MIT license covers the code. It does not grant rights to redistribute attendee data or someone else’s personal information. Use only directories you are authorized to access and respect event rules and people’s privacy.

Span is independent and unofficial, with no affiliation or endorsement from Lenny & Friends Summit, Lenny’s Newsletter, Zuddl, LinkedIn, or OpenAI. Software and results are provided as-is, without warranties. See [LICENSE](../LICENSE).
