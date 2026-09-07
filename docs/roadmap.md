# After v1: optional profile enrichment

The first community release builds a list from event attendee cards. It does not navigate individual profiles or promise an attendee's actual LinkedIn URL.

A later version can add a separate, optional, cancellable and resumable profile-enrichment pass. It must not block access to the initial list. Store event-supplied profile URLs with their source and collection time, independently of LinkedIn-export candidates and user decisions. A source-reported link is not automatically proof of ownership.

The native Attendee model reserves optional ProfileEvidence for that information. Missing evidence must remain normal and backward-compatible. Event records, identity candidates, and candidate-specific human decisions stay separate so adding enrichment does not discard saved confirmations or rejected pairings.

Before shipping enrichment: test profile navigation/back recovery, interrupted scans, missing and malformed URLs, duplicate names, stable event identifiers, stale details, consent and data-access constraints, and the added scan duration. Do not automatically open every LinkedIn page.
