#!/usr/bin/env python3
"""Adds a build to appcast.xml, the feed Sparkle reads.

Sparkle will not install an archive that isn't signed by the EdDSA key whose
public half is in the app's Info.plist, so the signature written here is what
makes updating safe without an Apple Developer ID. The private half never
touches the repository: it lives in the SPARKLE_PRIVATE_KEY secret and reaches
`sign_update` through the environment.

Usage:
    Scripts/appcast.py <version> <path-to-zip> <download-url>

The feed is committed rather than generated from scratch each time. Older
*other* versions are left as they were published: re-signing them would mean
downloading every archive ever published just to say the same thing about
them again.

The version being offered is the exception. A tag can be built more than once,
and a later run can replace the zip after this feed already names that
version. Sparkle checks the enclosure signature against the bytes it
downloads, so an item that already carries this version has its enclosure
rewritten — url, length and edSignature — from the zip passed in. The notes
stay; they come from the changelog, not from the archive.
"""

from __future__ import annotations

import email.utils
import html
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import changelog  # noqa: E402  — a sibling script, not a package

ROOT = Path(__file__).resolve().parent.parent
FEED = ROOT / "appcast.xml"


def github_repo() -> str:
    """owner/name. CI sets GITHUB_REPOSITORY; a local run reads origin."""
    env = os.environ.get("GITHUB_REPOSITORY", "").strip()
    if env:
        return env
    result = subprocess.run(
        ["git", "remote", "get-url", "origin"],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    url = result.stdout.strip()
    for prefix in ("git@github.com:", "https://github.com/", "ssh://git@github.com/"):
        if url.startswith(prefix):
            url = url[len(prefix) :]
            break
    if url.endswith(".git"):
        url = url[:-4]
    if not url:
        sys.exit("Could not tell which GitHub repository this is.")
    return url


REPO_SLUG = github_repo()
REPO = f"https://github.com/{REPO_SLUG}"
FEED_URL = f"https://raw.githubusercontent.com/{REPO_SLUG}/main/appcast.xml"

SKELETON = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Pulse</title>
        <link>{FEED_URL}</link>
        <description>Updates for Pulse.</description>
        <language>zh-CN</language>
    </channel>
</rss>
"""


def sign(archive: Path) -> tuple[str, str]:
    """The archive's EdDSA signature and length, from Sparkle's own tool."""
    tools = list((ROOT / ".build" / "artifacts").rglob("sign_update"))
    if not tools:
        sys.exit("sign_update not found — run `swift build` first so Sparkle's tools are fetched.")

    command = [str(tools[0])]

    # In CI the key comes from the secret and is piped in; on a developer's Mac
    # `generate_keys` has already put it in the login keychain and the tool
    # finds it there on its own.
    #
    # Through stdin, not `-s`: that flag is deprecated and explicitly refuses
    # newly generated keys, which is every key anyone would make today. It
    # fails with a message you only see if stderr is not swallowed, which is
    # the other half of why this cost a release run.
    key = os.environ.get("SPARKLE_PRIVATE_KEY", "").strip()
    if key:
        command += ["--ed-key-file", "-"]
    command.append(str(archive))

    result = subprocess.run(
        command,
        input=key + "\n" if key else None,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.exit(f"sign_update failed ({result.returncode}):\n{result.stderr.strip()}")

    output = result.stdout

    # It prints the two attributes ready to paste: sparkle:edSignature="…" length="…"
    parts = dict(
        piece.split("=", 1) for piece in output.strip().replace('" ', '"\n').split("\n")
    )
    signature = parts["sparkle:edSignature"].strip('"')
    length = parts["length"].strip('"')
    return signature, length


# Bookkeeping, not news: the version bump itself and the commit this script's
# own output produces.
BORING = re.compile(r"^(Pulse \d|Offer \d[\d.]* to Sparkle$)")

# Spacing only — **no colours and no fonts.** Sparkle injects a stylesheet of
# its own (`ReleaseNotesColorStyle.css`) that turns the text white under
# `prefers-color-scheme: dark` and leaves the background transparent so the
# update window shows through, and it sets the font to match the dialog. A feed
# that brings its own palette is fighting that, and loses in whichever
# appearance it guessed wrong about.
STYLE = """<style>
  h2 { font-size: 1.05em; margin: 0 0 .5em; }
  ul { margin: 0; padding-left: 1.2em; }
  li { margin: .3em 0; }
  p { margin: .8em 0 0; }
</style>"""


def previous_version(feed: str) -> str | None:
    """The newest version already in the feed, which is the one being replaced."""
    match = re.search(r"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>", feed)
    return match.group(1) if match else None


def changes(version: str, previous: str | None) -> list[str]:
    """The commit subjects, as a **fallback** when the changelog has no entry.

    Not the first choice, and it was: this repository takes direct commits, so
    the range runs to forty subjects a release and half of them say things like
    "Update README" — true, and meaningless to somebody deciding whether to
    install an update. A forgotten changelog entry should still ship something
    rather than an empty dialog, which is all this is for.
    """
    if not previous:
        return []

    result = subprocess.run(
        ["git", "log", f"v{previous}..v{version}", "--format=%s", "--reverse"],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    if result.returncode != 0:
        return []

    return [line for line in result.stdout.splitlines() if line and not BORING.match(line)]


def description(version: str, previous: str | None) -> str:
    """The release notes Sparkle shows, carried **in the feed**.

    Not a `sparkle:releaseNotesLink`, which is what this used to be: that is
    not a link the user clicks, it is a page Sparkle loads into the update
    window — so the whole GitHub release page, navigation bars and all, was
    rendered inside a small panel, and showed nothing at all without a network.

    This fork prefers Chinese (`CHANGELOG.zh-CN.md`) so the update dialog
    matches a Chinese Mac UI; English is the fallback if the ZH entry is missing.
    """
    written = changelog.entry(version, changelog.CHANGELOG_ZH) or changelog.entry(version)
    if written:
        listing = changelog.as_html(written)
    else:
        items = changes(version, previous)
        body = "".join(f"<li>{html.escape(line)}</li>" for line in items)
        listing = f"<ul>{body}</ul>" if body else ""

    link = f'<p><a href="{REPO}/releases/tag/v{version}">在 GitHub 查看更新说明</a></p>'
    inner = f"{STYLE}<h2>Pulse {html.escape(version)}</h2>{listing}{link}"

    # A CDATA section cannot contain its own terminator; nothing here should
    # produce one, but a commit subject is user-written text.
    return inner.replace("]]>", "]]&gt;")


def enclosure(url: str, length: str, signature: str) -> str:
    """The four-line enclosure this feed has always written.

    Kept in one place so a rewrite of an existing item is byte-for-byte the
    same shape as a newly inserted one. Sparkle reads the attributes; the
    whitespace is for the diff of a release that changed nothing else.
    """
    return (
        f'            <enclosure url="{url}"\n'
        f'                       length="{length}"\n'
        f'                       type="application/octet-stream"\n'
        f'                       sparkle:edSignature="{signature}" />'
    )


def render_item(version: str, url: str, signature: str, length: str, notes: str) -> str:
    """A new item. `enclosure()` is spliced in whole so its indent is not doubled."""
    published = email.utils.formatdate(localtime=False, usegmt=False)
    return (
        "        <item>\n"
        f"            <title>{version}</title>\n"
        f"            <pubDate>{published}</pubDate>\n"
        f"            <sparkle:version>{version}</sparkle:version>\n"
        f"            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
        "            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n"
        f"            <link>{REPO}/releases/tag/v{version}</link>\n"
        f"            <description><![CDATA[{notes}]]></description>\n"
        f"{enclosure(url, length, signature)}\n"
        "        </item>\n"
    )


# One item, in the indentation `render_item` writes and every entry in the
# committed feed uses. Non-greedy: a description does not contain `</item>`.
_ITEM = re.compile(r"        <item>\n.*?\n        </item>\n", re.DOTALL)

# The enclosure as `enclosure()` writes it. A looser match would still update
# the signature and could also reflow an entry nobody meant to touch.
_ENCLOSURE = re.compile(
    r'            <enclosure url="[^"]*"\n'
    r'                       length="[^"]*"\n'
    r'                       type="application/octet-stream"\n'
    r'                       sparkle:edSignature="[^"]*" />'
)


def version_marker(version: str) -> str:
    return f"<sparkle:version>{version}</sparkle:version>"


def replace_enclosure(feed: str, version: str, url: str, signature: str, length: str) -> str:
    """Rewrite the enclosure of `version` and copy every other item through.

    Notes, the publication date and the release-page link stay. The download
    url is the one passed in, which is the asset this run just published.
    Failing closed if the item is missing or oddly shaped: a silent no-op is
    how a rebuilt zip kept a signature for the zip it replaced.
    """
    marker = version_marker(version)
    found = False

    def rewrite(match: re.Match[str]) -> str:
        nonlocal found
        block = match.group(0)
        if marker not in block:
            return block
        if found:
            sys.exit(f"appcast.xml offers {version} more than once — check it by hand.")
        found = True
        updated, count = _ENCLOSURE.subn(enclosure(url, length, signature), block, count=1)
        if count != 1:
            sys.exit(
                f"appcast.xml offers {version} but its enclosure is not in the shape this expects — check it by hand."
            )
        return updated

    updated = _ITEM.sub(rewrite, feed)
    if not found:
        sys.exit(
            f"appcast.xml mentions {version} but not as an item this can rewrite — check it by hand."
        )
    return updated


def offer(feed: str, version: str, url: str, signature: str, length: str, notes: str) -> str:
    """The feed with `version` offered.

    Inserted at the top when the feed has no such item. When it does, only
    that item's enclosure changes — `notes` is ignored, so a second offer
    cannot wipe release notes that were already served. No other version is
    re-signed.
    """
    if version_marker(version) in feed:
        return replace_enclosure(feed, version, url, signature, length)

    # Newest first, which is the order Sparkle and every feed reader expect.
    anchor = "        <language>zh-CN</language>\n"
    if anchor not in feed:
        sys.exit("appcast.xml is not in the shape this expects — check it by hand.")
    item = render_item(version, url, signature, length, notes)
    return feed.replace(anchor, anchor + item, 1)


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)

    version, archive, url = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
    signature, length = sign(archive)

    feed = FEED.read_text() if FEED.exists() else SKELETON
    feed = re.sub(
        r"<link>https://raw\.githubusercontent\.com/[^/]+/Pulse/main/appcast\.xml</link>",
        f"<link>{FEED_URL}</link>",
        feed,
        count=1,
    )

    # Notes are computed only for a version the feed does not yet carry.
    # Re-offering the same version keeps the notes already there.
    if version_marker(version) in feed:
        feed = offer(feed, version, url, signature, length, "")
        print(f"appcast.xml replaces the {version} enclosure ({length} bytes)")
    else:
        notes = description(version, previous_version(feed))
        feed = offer(feed, version, url, signature, length, notes)
        print(f"appcast.xml now offers {version} ({length} bytes)")

    FEED.write_text(feed)


if __name__ == "__main__":
    main()
