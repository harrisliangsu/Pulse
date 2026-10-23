#!/usr/bin/env python3
"""The feed writer, without a private key and without touching appcast.xml.

`sign_update` needs SPARKLE_PRIVATE_KEY, which is not in the repository, so
these checks call `offer` with a signature the test invents. They never call
`sign` and they never write the feed. Run: python3 Scripts/appcast_test.py
"""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import appcast  # noqa: E402


def _item(feed: str, version: str) -> str:
    marker = appcast.version_marker(version)
    for match in appcast._ITEM.finditer(feed):
        block = match.group(0)
        if marker in block:
            return block
    raise AssertionError(f"no item for {version}")


class OfferTests(unittest.TestCase):
    def setUp(self) -> None:
        self.feed = appcast.offer(
            appcast.SKELETON,
            "1.2.0",
            "https://example.invalid/Blinky-1.2.0.zip",
            "sig-old",
            "100",
            "notes-for-1.2.0",
        )
        self.feed = appcast.offer(
            self.feed,
            "1.3.0",
            "https://example.invalid/Blinky-1.3.0.zip",
            "sig-new",
            "200",
            "notes-for-1.3.0",
        )

    def test_insert_keeps_only_the_newest_item(self) -> None:
        self.assertEqual(appcast.KEPT_ITEMS, 1)
        self.assertEqual(self.feed.count("<item>"), 1)
        self.assertIn(appcast.version_marker("1.3.0"), self.feed)
        self.assertNotIn(appcast.version_marker("1.2.0"), self.feed)
        current = _item(self.feed, "1.3.0")
        self.assertIn('sparkle:edSignature="sig-new"', current)
        self.assertIn('length="200"', current)
        self.assertIn("notes-for-1.3.0", current)
        self.assertNotIn("notes-for-1.2.0", self.feed)
        self.assertNotIn('sparkle:edSignature="sig-old"', self.feed)

    def test_same_version_replaces_enclosure_only(self) -> None:
        updated = appcast.offer(
            self.feed,
            "1.3.0",
            "https://example.invalid/Blinky-1.3.0-rebuilt.zip",
            "sig-rebuilt",
            "333",
            "notes-that-must-not-replace",
        )

        current = _item(updated, "1.3.0")
        self.assertIn('url="https://example.invalid/Blinky-1.3.0-rebuilt.zip"', current)
        self.assertIn('length="333"', current)
        self.assertIn('sparkle:edSignature="sig-rebuilt"', current)
        self.assertIn("notes-for-1.3.0", current)
        self.assertNotIn("notes-that-must-not-replace", updated)
        self.assertNotIn('sparkle:edSignature="sig-new"', updated)
        self.assertEqual(updated.count("<item>"), 1)

    def test_reoffer_of_the_newest_drops_older_items(self) -> None:
        older = appcast.render_item(
            "1.2.0",
            "https://example.invalid/Blinky-1.2.0.zip",
            "sig-old",
            "100",
            "notes-for-1.2.0",
        )
        newer = appcast.render_item(
            "1.3.0",
            "https://example.invalid/Blinky-1.3.0.zip",
            "sig-new",
            "200",
            "notes-for-1.3.0",
        )
        anchor = "        <language>zh-CN</language>\n"
        feed = appcast.SKELETON.replace(anchor, anchor + newer + older, 1)
        self.assertEqual(feed.count("<item>"), 2)

        updated = appcast.offer(
            feed,
            "1.3.0",
            "https://example.invalid/Blinky-1.3.0-rebuilt.zip",
            "sig-rebuilt",
            "333",
            "notes-that-must-not-replace",
        )
        self.assertEqual(updated.count("<item>"), 1)
        self.assertIn("notes-for-1.3.0", updated)
        self.assertIn('sparkle:edSignature="sig-rebuilt"', updated)
        self.assertNotIn("notes-for-1.2.0", updated)
        self.assertNotIn(appcast.version_marker("1.2.0"), updated)

    def test_described_insert_keeps_one_item(self) -> None:
        notes = '<description xml:lang="en"><![CDATA[only-this-version]]></description>'
        updated = appcast.insert_described(
            self.feed,
            "1.4.0",
            "https://example.invalid/Blinky-1.4.0.zip",
            "sig-described",
            "9",
            notes,
        )
        self.assertEqual(updated.count("<item>"), 1)
        self.assertIn("only-this-version", updated)
        self.assertNotIn(appcast.version_marker("1.3.0"), updated)

    def test_identical_reoffer_is_a_no_diff(self) -> None:
        again = appcast.offer(
            self.feed,
            "1.3.0",
            "https://example.invalid/Blinky-1.3.0.zip",
            "sig-new",
            "200",
            "",
        )
        self.assertEqual(again, self.feed)

    def test_broken_enclosure_does_not_noop(self) -> None:
        broken = self.feed.replace(
            appcast.enclosure(
                "https://example.invalid/Blinky-1.3.0.zip",
                "200",
                "sig-new",
            ),
            '<enclosure url="https://example.invalid/short" />',
            1,
        )
        with self.assertRaises(SystemExit) as caught:
            appcast.offer(broken, "1.3.0", "https://example.invalid/x", "sig", "1", "")
        self.assertIn("enclosure", str(caught.exception))

    def test_committed_feed_shape(self) -> None:
        """The regex has to match the file Sparkle actually reads.

        Versions are taken from the file, so a later release does not rot the
        check. The file itself is not written.
        """
        path = appcast.FEED
        original = path.read_text()
        versions = re.findall(r"<sparkle:version>([^<]+)</sparkle:version>", original)
        self.assertEqual(len(versions), appcast.KEPT_ITEMS)
        self.assertEqual(original.count("<item>"), appcast.KEPT_ITEMS)
        newest = versions[0]

        updated = appcast.offer(
            original,
            newest,
            "https://example.invalid/rebuilt.zip",
            "sig-from-test",
            "42",
            "do-not-write-this",
        )

        self.assertEqual(path.read_text(), original)
        self.assertEqual(updated.count("<item>"), 1)
        current = _item(updated, newest)
        self.assertIn('sparkle:edSignature="sig-from-test"', current)
        self.assertIn('length="42"', current)
        self.assertIn('url="https://example.invalid/rebuilt.zip"', current)
        self.assertNotIn("do-not-write-this", updated)
        # Notes and the publication date are the part a reader already saw.
        # This fork's newest item has one description per language
        # (`<description xml:lang="…">`), not a single bare `<description>`.
        notes = re.findall(
            r'<description(?: xml:lang="[^"]+")?><!\[CDATA\[',
            _item(original, newest),
        )
        self.assertGreaterEqual(len(notes), 1)
        for note in notes:
            self.assertIn(note, current)
        pub = re.search(r"<pubDate>([^<]+)</pubDate>", _item(original, newest))
        assert pub is not None
        self.assertIn(pub.group(1), current)

        signature = re.search(r'sparkle:edSignature="([^"]*)"', _item(original, newest))
        length = re.search(r'length="([^"]*)"', _item(original, newest))
        url = re.search(r'<enclosure url="([^"]*)"', _item(original, newest))
        assert signature and length and url
        same = appcast.offer(original, newest, url.group(1), signature.group(1), length.group(1), "")
        self.assertEqual(same, original)


if __name__ == "__main__":
    unittest.main()
