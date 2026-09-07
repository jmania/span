import csv
import tempfile
import unittest
from pathlib import Path

from summit_network.matching import Connection, best_match, match_files, normalized_name
from summit_network.review import ReviewStore


class MatchingTests(unittest.TestCase):
    def test_normalizes_accents_suffixes_and_punctuation(self):
        self.assertEqual(normalized_name("José O’Neil, PhD"), "jose o neil")

    def test_exact_name_match(self):
        connections = [Connection("Maya Chen", "Example Corp", "Product", "https://example.test/a", "")]
        match, confidence, reason = best_match("Maya Chen", "Example Corp", connections)
        self.assertEqual(match, connections[0])
        self.assertGreaterEqual(confidence, 0.97)
        self.assertIn("exact", reason)

    def test_duplicate_name_is_not_guessed(self):
        connections = [
            Connection("Alex Kim", "Acme", "Engineer", "", ""),
            Connection("Alex Kim", "Beta", "Designer", "", ""),
        ]
        match, _, reason = best_match("Alex Kim", "", connections)
        self.assertIsNone(match)
        self.assertIn("multiple", reason)

    def test_file_workflow(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            attendees = root / "attendees.csv"
            connections = root / "Connections.csv"
            output = root / "results.csv"
            attendees.write_text("name,details\nMaya Chen,Example Corp\nDifferent Person,Somewhere\n", encoding="utf-8")
            connections.write_text(
                "Notes:\nYour export may contain an explanatory preamble.\n\n"
                "First Name,Last Name,URL,Company,Position\n"
                "Maya,Chen,https://example.test/a,Example Corp,Product\n",
                encoding="utf-8",
            )
            counts = match_files(attendees, connections, output)
            self.assertEqual(counts, {"1st": 1, "review": 1})
            with output.open(newline="", encoding="utf-8") as source:
                rows = list(csv.DictReader(source))
            self.assertEqual(rows[0]["degree"], "1st")
            self.assertEqual(rows[1]["degree"], "review")

    def test_review_decision_is_persisted(self):
        with tempfile.TemporaryDirectory() as folder:
            results = Path(folder) / "results.csv"
            results.write_text(
                "name,details,degree,confidence,linkedin_url,matched_connection,match_reason,reviewed_at\n"
                "A Person,Acme,review,,,,no first-degree name match,\n",
                encoding="utf-8",
            )
            store = ReviewStore(results)
            store.classify(0, "2nd")
            with results.open(newline="", encoding="utf-8") as source:
                row = next(csv.DictReader(source))
            self.assertEqual(row["degree"], "2nd")
            self.assertTrue(row["reviewed_at"])


if __name__ == "__main__":
    unittest.main()
