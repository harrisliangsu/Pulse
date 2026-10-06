#!/usr/bin/env python3
"""Adds a build to appcast.xml, the feed Sparkle reads.

Sparkle will not install an archive that isn't signed by the EdDSA key whose
public half is in the app's Info.plist, so the signature written here is what
makes updating safe without an Apple Developer ID. The private half never
touches the repository: it lives in the SPARKLE_PRIVATE_KEY secret and reaches
`sign_update` through the environment.

Usage:
    Scripts/appcast.py <version> <path-to-zip> <download-url>
    Scripts/appcast.py --notes <version>     # rewrite one item's notes only

**One language in the update window.** This fork writes the changelog in two
files (Chinese in CHANGELOG.zh-CN.md, English in CHANGELOG.md). Each new item
carries one `<description xml:lang="…">` per language and Sparkle shows the one
the system's preferred languages pick. Chinese goes out as both `zh-Hans` and
`zh-Hant`. Japanese and Korean readers get English. Pulse can also be set to a
language other than the system's, which Sparkle cannot see, so the script
writes one feed per language as well (`appcast-zh.xml`, `appcast-en.xml`) and
the app reads the one for the language it is set to.

Every feed URL is this repository's own file on GitHub
(`raw.githubusercontent.com/<owner>/Pulse/main/`). This fork does not publish
to, or fall back onto, update.qunqin.org.

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

# Chinese notes are offered under both written Chinese languages. The English
# notes are the feed Japanese and Korean readers get. `feed` is the one-language
# copy written beside appcast.xml.
NOTE_LANGUAGES: dict[str, dict[str, object]] = {
    "中文": {
        "langs": ["zh-Hans", "zh-Hant"],
        "feed": "appcast-zh.xml",
        "link": "在 GitHub 查看更新说明",
        "path": changelog.CHANGELOG_ZH,
    },
    "English": {
        "langs": ["en"],
        "feed": "appcast-en.xml",
        "link": "Release notes on GitHub",
        "path": changelog.CHANGELOG,
    },
}


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
    if "@" in url and "github.com" in url:
        url = "https://" + url.split("@", 1)[1]
    for prefix in ("git@github.com:", "https://github.com/", "ssh://git@github.com/"):
        if url.startswith(prefix):
            url = url[len(prefix) :]
            break
    if url.endswith(".git"):
        url = url[:-4]
    if not url or "/" not in url:
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


def notes_html(version: str, listing: str, link_text: str) -> str:
    """One language's notes as the update window shows them."""
    link = f'<p><a href="{REPO}/releases/tag/v{version}">{html.escape(link_text)}</a></p>'
    inner = f"{STYLE}<h2>Pulse {html.escape(version)}</h2>{listing}{link}"
    # A CDATA section cannot contain its own terminator; nothing here should
    # produce one, but a commit subject is user-written text.
    return inner.replace("]]>", "]]&gt;")


def descriptions(version: str, previous: str | None) -> str:
    """The `<description>` elements of one item, one per language we have.

    Chinese from CHANGELOG.zh-CN.md is offered as `zh-Hans` and `zh-Hant`.
    English from CHANGELOG.md is offered as `en`. A version with only one of
    the two files still gets that language. With neither, the commit subjects
    are a single description with no `xml:lang`.
    """
    elements: list[str] = []
    for spec in NOTE_LANGUAGES.values():
        path = spec["path"]
        written = changelog.entry(version, path) if isinstance(path, Path) else None
        if not written:
            continue
        notes = notes_html(version, changelog.as_html(written), str(spec["link"]))
        langs = spec["langs"]
        assert isinstance(langs, list)
        for lang in langs:
            elements.append(f'<description xml:lang="{lang}"><![CDATA[{notes}]]></description>')
    if elements:
        return "\n            ".join(elements)

    items = changes(version, previous)
    body = "".join(f"<li>{html.escape(line)}</li>" for line in items)
    listing = f"<ul>{body}</ul>" if body else ""
    return (
        "<description><![CDATA["
        f"{notes_html(version, listing, 'Release notes on GitHub')}"
        "]]></description>"
    )


ITEM = re.compile(r"        <item>\n.*?        </item>\n", re.S)
DESCRIPTION = re.compile(
    r'[ \t]*<description(?: xml:lang="([^"]+)")?><!\[CDATA\[.*?\]\]></description>\n',
    re.S,
)


def single_language(feed: str, langs: list[str]) -> str:
    """The feed with each item's notes cut to one language.

    An item with notes in several languages keeps only the first of `langs`
    it has, under no `xml:lang` (one node needs none); an older item with one
    bilingual description is left as it is.
    """

    def cut(match: re.Match[str]) -> str:
        item = match.group(0)
        found = DESCRIPTION.findall(item)
        if len([lang for lang in found if lang]) < 2:
            return item
        keep = next((lang for lang in langs if lang in found), None)
        if keep is None:
            return item

        def one(description: re.Match[str]) -> str:
            if description.group(1) != keep:
                return ""
            return description.group(0).replace(f' xml:lang="{keep}"', "", 1)

        return DESCRIPTION.sub(one, item)

    return ITEM.sub(cut, feed)


def feed_file_url(name: str) -> str:
    return f"https://raw.githubusercontent.com/{REPO_SLUG}/main/{name}"


def write_feeds(feed: str) -> None:
    """appcast.xml and its one-language copies, all on this repository."""
    feed = re.sub(
        r"<link>https://raw\.githubusercontent\.com/[^<]+/appcast(?:-[a-z]+)?\.xml</link>",
        f"<link>{FEED_URL}</link>",
        feed,
        count=1,
    )
    FEED.write_text(feed)
    for spec in NOTE_LANGUAGES.values():
        langs = [str(lang) for lang in spec["langs"]]  # type: ignore[union-attr]
        name = str(spec["feed"])
        copy = single_language(feed, langs).replace(FEED_URL, feed_file_url(name), 1)
        (ROOT / name).write_text(copy)


def rewrite_notes(version: str) -> None:
    """Replaces the notes of an item already in the feed, nothing else: the
    enclosure, its signature and the dates stay as they were served."""
    feed = FEED.read_text()
    for match in ITEM.finditer(feed):
        item = match.group(0)
        if f"<sparkle:version>{version}</sparkle:version>" not in item:
            continue
        previous = None
        older = feed[match.end() :]
        found = re.search(r"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>", older)
        if found:
            previous = found.group(1)
        stripped = DESCRIPTION.sub("", item)
        anchor = "            <enclosure "
        if anchor not in stripped:
            sys.exit(f"The {version} item is not in the shape this expects — check it by hand.")
        rewritten = stripped.replace(anchor, f"            {descriptions(version, previous)}\n{anchor}", 1)
        write_feeds(feed[: match.start()] + rewritten + feed[match.end() :])
        print(f"Rewrote the notes for {version}.")
        return
    sys.exit(f"appcast.xml has no item for {version}.")


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
    """A new item whose notes are one CDATA body. `enclosure()` is spliced in whole."""
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


def render_described_item(version: str, url: str, signature: str, length: str, notes: str) -> str:
    """A new item whose `notes` are already `<description>` elements."""
    published = email.utils.formatdate(localtime=False, usegmt=False)
    return (
        "        <item>\n"
        f"            <title>{version}</title>\n"
        f"            <pubDate>{published}</pubDate>\n"
        f"            <sparkle:version>{version}</sparkle:version>\n"
        f"            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
        "            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n"
        f"            <link>{REPO}/releases/tag/v{version}</link>\n"
        f"            {notes}\n"
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

    `notes` here is the inside of one description, which is what the tests
    and a feed that predates per-language descriptions pass. `main` inserts a
    new release through `render_described_item` so each language is its own
    element.
    """
    if version_marker(version) in feed:
        return replace_enclosure(feed, version, url, signature, length)

    # Newest first, which is the order Sparkle and every feed reader expect.
    # This fork's committed feed says zh-CN, not en.
    anchor = "        <language>zh-CN</language>\n"
    if anchor not in feed:
        sys.exit("appcast.xml is not in the shape this expects — check it by hand.")
    item = render_item(version, url, signature, length, notes)
    return feed.replace(anchor, anchor + item, 1)


def insert_described(feed: str, version: str, url: str, signature: str, length: str, notes: str) -> str:
    """Insert a new item whose notes are already description elements."""
    anchor = "        <language>zh-CN</language>\n"
    if anchor not in feed:
        sys.exit("appcast.xml is not in the shape this expects — check it by hand.")
    item = render_described_item(version, url, signature, length, notes)
    return feed.replace(anchor, anchor + item, 1)


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "--notes":
        rewrite_notes(sys.argv[2])
        return
    if len(sys.argv) != 4:
        sys.exit(__doc__)

    version, archive, url = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
    signature, length = sign(archive)

    feed = FEED.read_text() if FEED.exists() else SKELETON
    feed = re.sub(
        r"<link>https://raw\.githubusercontent\.com/[^<]+/appcast(?:-[a-z]+)?\.xml</link>",
        f"<link>{FEED_URL}</link>",
        feed,
        count=1,
    )

    # Notes are computed only for a version the feed does not yet carry.
    # Re-offering the same version keeps the notes already there and rewrites
    # the enclosure, which is the zip this run just published.
    if version_marker(version) in feed:
        feed = offer(feed, version, url, signature, length, "")
        print(f"appcast.xml replaces the {version} enclosure ({length} bytes)")
    else:
        notes = descriptions(version, previous_version(feed))
        feed = insert_described(feed, version, url, signature, length, notes)
        print(f"appcast.xml now offers {version} ({length} bytes)")

    write_feeds(feed)


if __name__ == "__main__":
    main()
