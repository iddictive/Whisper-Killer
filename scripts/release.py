#!/usr/bin/env python3
"""Prepare and validate one immutable version/changelog release contract."""
import argparse
import datetime
import json
import plistlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLIST = Path("Sources/WhisperFree/Resources/Info.plist")
HEADER = re.compile(r"^## \[([^\]]+)\](?: - (\d{4}-\d{2}-\d{2}))?\s*$", re.M)


def version_key(value):
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", value):
        raise ValueError(f"Invalid release version: {value}")
    return tuple(map(int, value.split(".")))


def successor(version):
    if not re.fullmatch(r"\d+\.\d+", version):
        raise ValueError("Automatic preparation requires the current major.minor version line")
    major, minor = version.split(".")
    return f"{major}.{int(minor) + 1}"


def sections(markdown):
    matches = list(HEADER.finditer(markdown))
    result = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(markdown)
        body = markdown[match.end():end].strip().removesuffix("---").strip()
        result.append((match.group(1), match.group(2), body, match.start(), end))
    names = [row[0] for row in result]
    if len(names) != len(set(names)) or not names or names[0] != "Unreleased":
        raise ValueError("Changelog must start with one Unreleased section and have unique versions")
    return result


def has_notes(body):
    return bool(re.search(r"^[-*] \S", body, re.M))


def contract(root):
    markdown = (root / "CHANGELOG.md").read_text()
    rows = sections(markdown)
    released = rows[1:]
    if not released:
        raise ValueError("Changelog has no numbered release")
    keys = [version_key(row[0]) for row in released]
    if keys != sorted(keys, reverse=True):
        raise ValueError("Changelog releases must be newest first")
    version, date, notes, _, _ = released[0]
    if not date or not has_notes(notes):
        raise ValueError("Latest release needs a date and nonempty release notes")
    datetime.date.fromisoformat(date)
    info = plistlib.loads((root / PLIST).read_bytes())
    if any(info.get(key) != version for key in ("CFBundleShortVersionString", "CFBundleVersion")):
        raise ValueError("Info.plist versions must equal the latest numbered changelog section")
    return markdown, rows, version, notes


def tags(root, remote=None):
    command = (["git", "ls-remote", "--tags", "--refs", remote] if remote
               else ["git", "tag", "--list", "v*"])
    output = subprocess.check_output(command, cwd=root, text=True)
    names = [line.split("refs/tags/")[-1] for line in output.splitlines()]
    return [tag[1:] for tag in names if re.fullmatch(r"v\d+\.\d+(?:\.\d+)?", tag)]


def plan(root, remote=None):
    _, rows, version, notes = contract(root)
    known = tags(root, remote)
    latest = max(known, key=version_key) if known else None
    if latest is None:
        raise ValueError("No release tags found; refuse to guess the release baseline")
    if version_key(version) < version_key(latest):
        raise ValueError("Checkout version is behind the latest tag")
    publish = version != latest
    if publish and version != successor(latest):
        raise ValueError(f"Prepared version must be the next version: {successor(latest)}")
    if publish and has_notes(rows[0][2]):
        raise ValueError("Unreleased still contains changes; prepare the release before publishing")
    return {"version": version, "tag": f"v{version}", "publish": publish,
            "notes": notes, "reason": "prepared release" if publish else "version already tagged; no publication"}


def prepare(root, date, remote=None):
    markdown, rows, current, _ = contract(root)
    known = tags(root, remote)
    latest = max(known, key=version_key) if known else None
    if latest is None or version_key(current) > version_key(latest):
        raise ValueError("Current version is not tagged yet; publish it before preparing another release")
    if version_key(current) < version_key(latest):
        raise ValueError("Checkout is behind the latest tag; reconcile it before preparing a release")
    body = rows[0][2]
    if not has_notes(body):
        raise ValueError("Unreleased is empty; refusing to create an empty release")
    version = successor(current)
    datetime.date.fromisoformat(date)
    start, end = rows[0][3:]
    updated = markdown[:start] + f"## [Unreleased]\n\n## [{version}] - {date}\n\n{body}\n\n---\n\n" + markdown[end:]
    # Preserve plist formatting; validate both substitutions before writing either file.
    plist = (root / PLIST).read_text()
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        pattern = rf"(<key>{key}</key>\s*<string>)[^<]+(</string>)"
        plist, count = re.subn(pattern, lambda m: m[1] + version + m[2], plist)
        if count != 1:
            raise ValueError(f"Expected exactly one {key}")
    (root / PLIST).write_text(plist)
    (root / "CHANGELOG.md").write_text(updated)
    return version


def verify_bundle(root, bundle):
    markdown, _, version, _ = contract(root)
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        if info.get(key) != version:
            raise ValueError(f"Packaged {key} does not match {version}")
    if (bundle / "Contents/Resources/CHANGELOG.md").read_text() != markdown:
        raise ValueError("Packaged changelog differs from the release source")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "check", "plan", "verify-bundle"])
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--date", default=datetime.datetime.now(datetime.timezone.utc).date().isoformat())
    parser.add_argument("--notes", type=Path)
    parser.add_argument("--github-output", type=Path)
    parser.add_argument("--require-new", action="store_true")
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--remote", help="Read authoritative tags from this remote without changing local refs")
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            print(f"Prepared {prepare(args.root, args.date, args.remote)}. Review and commit CHANGELOG.md and Info.plist together.")
        elif args.command == "check":
            print(f"Release metadata is consistent: {contract(args.root)[2]}")
        elif args.command == "verify-bundle":
            if not args.bundle:
                raise ValueError("--bundle is required")
            verify_bundle(args.root, args.bundle)
            print("Packaged version and changelog match the source")
        else:
            result = plan(args.root, args.remote)
            if args.require_new and not result["publish"]:
                raise ValueError("Release version already exists; refusing to overwrite it")
            if args.notes:
                args.notes.write_text(result["notes"] + "\n")
            if args.github_output:
                with args.github_output.open("a") as output:
                    output.write(f"version={result['version']}\npublish={str(result['publish']).lower()}\n")
            print(json.dumps({key: value for key, value in result.items() if key != "notes"}))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Release error: {error}\n")


if __name__ == "__main__":
    main()
