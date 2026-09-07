from __future__ import annotations

import csv
import re
import unicodedata
from dataclasses import dataclass
from difflib import SequenceMatcher
from pathlib import Path


SUFFIXES = {"jr", "sr", "ii", "iii", "iv", "phd", "mba", "md", "esq"}
WORD_RE = re.compile(r"[a-z0-9]+")


def normalized_name(value: str) -> str:
    value = unicodedata.normalize("NFKD", value or "")
    value = "".join(character for character in value if not unicodedata.combining(character))
    words = WORD_RE.findall(value.casefold())
    while words and words[-1] in SUFFIXES:
        words.pop()
    return " ".join(words)


def tokens(value: str) -> set[str]:
    return {word for word in WORD_RE.findall(normalized_name(value)) if len(word) > 1}


def detail_overlap(left: str, right: str) -> float:
    a, b = tokens(left), tokens(right)
    if not a or not b:
        return 0.0
    return len(a & b) / min(len(a), len(b))


@dataclass(frozen=True)
class Connection:
    name: str
    company: str
    position: str
    url: str
    email: str

    @property
    def details(self) -> str:
        return " ".join(part for part in (self.company, self.position) if part)


def read_connections(path: Path) -> list[Connection]:
    with path.open(newline="", encoding="utf-8-sig") as source:
        raw_rows = csv.reader(source)
        headers = None
        for candidate in raw_rows:
            normalized = {value.casefold().strip() for value in candidate}
            if "name" in normalized or {"first name", "last name"}.issubset(normalized):
                headers = candidate
                break
        if headers is None:
            raise ValueError("The connections file has no header row")
        rows = csv.DictReader(source, fieldnames=headers)
        lower_headers = {header.casefold().strip(): header for header in headers}

        def column(*names: str) -> str | None:
            return next((lower_headers[name.casefold()] for name in names if name.casefold() in lower_headers), None)

        first_col = column("First Name", "first_name", "first")
        last_col = column("Last Name", "last_name", "last")
        full_col = column("Name", "full_name", "Full Name")
        if not full_col and not (first_col and last_col):
            raise ValueError("Expected Name, or First Name and Last Name, in the connections CSV")
        company_col = column("Company", "organization")
        position_col = column("Position", "title", "job title")
        url_col = column("URL", "LinkedIn URL", "profile url")
        email_col = column("Email Address", "email")

        connections = []
        for row in rows:
            name = row.get(full_col, "") if full_col else f"{row.get(first_col, '')} {row.get(last_col, '')}"
            if not normalized_name(name):
                continue
            connections.append(
                Connection(
                    name=name.strip(),
                    company=(row.get(company_col, "") if company_col else "").strip(),
                    position=(row.get(position_col, "") if position_col else "").strip(),
                    url=(row.get(url_col, "") if url_col else "").strip(),
                    email=(row.get(email_col, "") if email_col else "").strip(),
                )
            )
    return connections


def best_match(name: str, details: str, connections: list[Connection]) -> tuple[Connection | None, float, str]:
    wanted = normalized_name(name)
    exact = [connection for connection in connections if normalized_name(connection.name) == wanted]
    if len(exact) == 1:
        overlap = detail_overlap(details, exact[0].details)
        return exact[0], 1.0 if overlap else 0.97, "exact name"
    if len(exact) > 1:
        ranked = sorted(exact, key=lambda item: detail_overlap(details, item.details), reverse=True)
        overlap = detail_overlap(details, ranked[0].details)
        if overlap >= 0.25:
            return ranked[0], min(1.0, 0.96 + overlap * 0.04), "exact name; details disambiguated"
        return None, 0.0, "multiple connections have this name"

    ranked: list[tuple[float, float, Connection]] = []
    for connection in connections:
        ratio = SequenceMatcher(None, wanted, normalized_name(connection.name)).ratio()
        if ratio < 0.88:
            continue
        overlap = detail_overlap(details, connection.details)
        ranked.append((ratio, overlap, connection))
    ranked.sort(key=lambda item: (item[0], item[1]), reverse=True)
    if not ranked:
        return None, 0.0, "no first-degree name match"

    ratio, overlap, candidate = ranked[0]
    second_ratio = ranked[1][0] if len(ranked) > 1 else 0.0
    if ratio >= 0.97 and ratio - second_ratio >= 0.03:
        return candidate, ratio * 0.96 + overlap * 0.04, "high-confidence fuzzy name"
    if ratio >= 0.92 and overlap >= 0.34 and ratio - second_ratio >= 0.02:
        return candidate, ratio * 0.8 + overlap * 0.2, "fuzzy name plus matching details"
    return None, ratio, f"possible match: {candidate.name}"


def match_files(attendees_path: Path, connections_path: Path, output_path: Path) -> dict[str, int]:
    connections = read_connections(connections_path)
    with attendees_path.open(newline="", encoding="utf-8-sig") as source:
        attendees = list(csv.DictReader(source))
    if not attendees or "name" not in attendees[0]:
        raise ValueError("The attendee CSV must include a name column")

    counts = {"1st": 0, "review": 0}
    fieldnames = [
        "name", "details", "degree", "confidence", "linkedin_url",
        "matched_connection", "match_reason", "reviewed_at",
    ]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as destination:
        writer = csv.DictWriter(destination, fieldnames=fieldnames)
        writer.writeheader()
        for attendee in attendees:
            name = (attendee.get("name") or "").strip()
            details = (attendee.get("details") or "").strip()
            connection, confidence, reason = best_match(name, details, connections)
            degree = "1st" if connection else "review"
            counts[degree] += 1
            writer.writerow(
                {
                    "name": name,
                    "details": details,
                    "degree": degree,
                    "confidence": f"{confidence:.3f}" if confidence else "",
                    "linkedin_url": connection.url if connection else "",
                    "matched_connection": connection.name if connection else "",
                    "match_reason": reason,
                    "reviewed_at": "",
                }
            )
    return counts
