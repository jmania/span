from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .matching import match_files
from .review import serve_review


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="summit-network", description="Map event attendees to your own network data")
    subcommands = root.add_subparsers(dest="command", required=True)

    match = subcommands.add_parser("match", help="Match attendees to a LinkedIn Connections.csv export")
    match.add_argument("attendees", type=Path)
    match.add_argument("connections", type=Path)
    match.add_argument("-o", "--output", type=Path, default=Path("network-results.csv"))

    review = subcommands.add_parser("review", help="Review unmatched attendees locally in a browser")
    review.add_argument("results", type=Path)
    review.add_argument("--port", type=int, default=0)
    review.add_argument("--no-open", action="store_true")
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "match":
            counts = match_files(args.attendees, args.connections, args.output)
            print(f"Wrote {args.output}: {counts['1st']} first-degree matches; {counts['review']} need review")
        elif args.command == "review":
            serve_review(args.results, port=args.port, open_browser=not args.no_open)
    except (OSError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
