#!/bin/bash
# CI-only publisher; metadata validation and artifact verification run first.
set -euo pipefail

: "${VERSION:?Prepared version is required}"
: "${GITHUB_SHA:?Tested commit is required}"
: "${GITHUB_REPOSITORY:?Release repository is required}"
: "${RUNNER_TEMP:?Release notes directory is required}"

test -s "WhisperKiller-$VERSION.dmg"
test -s "$RUNNER_TEMP/release-notes.md"

# Atomic creation rejects an existing tag, including one created after preflight.
gh api "repos/$GITHUB_REPOSITORY/git/refs" --method POST \
    -f "ref=refs/tags/v$VERSION" -f "sha=$GITHUB_SHA"
gh release create "v$VERSION" "WhisperKiller-$VERSION.dmg" \
    --repo "$GITHUB_REPOSITORY" --verify-tag \
    --title "WhisperKiller v$VERSION" \
    --notes-file "$RUNNER_TEMP/release-notes.md"
