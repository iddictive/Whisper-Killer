# Release version and changelog contract

`CHANGELOG.md` is the authored release history. Its newest numbered section is
the version also stored in both `Info.plist` version fields. `Unreleased` holds
only changes after that release. README links to the live release instead of
copying a version number.

## Preparation and publication

1. Keep user-facing changes in `Unreleased` while implementing a batch.
2. Run `make release-prepare` after the batch is ready. It reads remote tags and
   finalizes the notes and the next version together. It refuses empty notes,
   stale metadata, or a previous prepared version that is not yet tagged.
3. Review the exact notes and version, run `make test`, and commit both files
   with the implementation. Push to `main` only when this batch should publish.
4. CI validates metadata before building. An already released version performs
   tests without republishing. A new version requires empty `Unreleased`, so
   unfinished notes cannot silently enter a released binary.
5. The workflow serializes releases and rechecks authoritative tags before
   publication. `scripts/publish_release.sh` atomically creates the tag at the
   tested commit and creates a new release. It fails on an existing tag or
   release rather than overwriting it or allocating another version on retry.

`scripts/release.py` owns validation, preparation, notes extraction, and packaged
metadata comparison. The workflow consumes its version output for the release
tag/name and DMG filename, its exact section body for GitHub notes, and copies
the source changelog into the app before signing. `make test` owns its regression
matrix; no separate Codex launcher action is needed for this maintainer helper.

## Runtime readers

The installed app uses its bundle version and the corresponding tag, with a
version-scoped cache. It does not substitute `Unreleased` for missing historical
notes. The dev app may show its bundled working changelog. The updater reads the
selected GitHub release body, with an exact-version tagged changelog fallback.

## Verification and recovery

- `python3 scripts/release.py check` validates source version/date/notes.
- `python3 scripts/release.py plan` explains whether this checkout publishes;
  CI runs it after checkout with full tags and again before publication.
- `python3 scripts/release.py verify-bundle --bundle PATH` compares packaged
  version fields and changelog with the prepared source before signing.
- After publication, resolve the remote tag to the tested commit, compare the
  GitHub release body with the section extracted by `scripts/release.py`, and
  download the named DMG. Compare its SHA-256 with the published asset digest;
  mount it read-only, verify its signature, and run `verify-bundle` against the
  mounted app. A green workflow alone does not establish artifact agreement.
- Rerun `plan --remote origin` after publication: the same version must report
  no publication. Report the installed application's version separately;
  publishing a release does not establish that a local installation updated.
- A failed build before publication may be retried from the same commit.
- If a tag already exists but its release upload is incomplete, stop and inspect
  that exact release; repair it deliberately instead of silently overwriting an
  existing artifact or creating a new version to hide the failure.

Historical sections 3.52–3.57 were reconstructed from their published tag
boundaries and publication dates. This source repair does not rewrite old tags,
published DMGs, or existing GitHub release descriptions.
