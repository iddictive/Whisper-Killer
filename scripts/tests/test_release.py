"""Release identity must agree across source, plan, and packaged metadata."""
import importlib.util
import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("release", Path(__file__).parents[1] / "release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="whisper-release-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Release Test")
        self.write_fixture()
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        self.git("tag", "v3.56")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True, stderr=subprocess.STDOUT)

    def write_fixture(self, pending="- Future change", version="3.56"):
        (self.root / "CHANGELOG.md").write_text(
            f"# Changelog\n\n## [Unreleased]\n\n### Fixed\n{pending}\n\n---\n\n"
            f"## [{version}] - 2026-09-22\n\n### Added\n- Previous change\n"
        )
        path = self.root / release.PLIST
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(plistlib.dumps({"CFBundleShortVersionString": version, "CFBundleVersion": version}))

    def test_prepare_plan_and_repeat_preserve_one_release_identity(self):
        self.assertFalse(release.plan(self.root)["publish"])
        self.assertEqual(release.prepare(self.root, "2026-09-23"), "3.57")
        plan = release.plan(self.root)
        self.assertTrue(plan["publish"])
        self.assertEqual(plan["tag"], "v3.57")
        self.assertEqual(plan["notes"], "### Fixed\n- Future change")
        self.assertNotIn("Previous change", plan["notes"])
        snapshot = (self.root / "CHANGELOG.md").read_bytes()
        with self.assertRaisesRegex(ValueError, "not tagged"):
            release.prepare(self.root, "2026-09-24")
        self.assertEqual(snapshot, (self.root / "CHANGELOG.md").read_bytes())
        self.git("add", ".")
        self.git("commit", "-qm", "prepared")
        self.git("tag", "v3.57")
        self.assertFalse(release.plan(self.root)["publish"])

    def test_inconsistent_and_unprepared_inputs_fail_closed(self):
        for case in ("empty", "mismatch", "unfinished", "duplicate", "skipped", "major", "stale"):
            with self.subTest(case=case):
                self.write_fixture()
                if case == "empty":
                    self.write_fixture(pending="")
                    operation = lambda: release.prepare(self.root, "2026-09-23")
                elif case == "mismatch":
                    path = self.root / release.PLIST
                    info = plistlib.loads(path.read_bytes())
                    info["CFBundleVersion"] = "3.51"
                    path.write_bytes(plistlib.dumps(info))
                    operation = lambda: release.contract(self.root)
                elif case == "unfinished":
                    self.write_fixture(version="3.57")
                    operation = lambda: release.plan(self.root)
                elif case == "duplicate":
                    path = self.root / "CHANGELOG.md"
                    path.write_text(path.read_text() + "\n## [3.56] - 2026-09-22\n- Duplicate\n")
                    operation = lambda: release.contract(self.root)
                elif case in ("skipped", "major"):
                    self.write_fixture(pending="", version="3.58" if case == "skipped" else "4.0")
                    operation = lambda: release.plan(self.root)
                else:
                    self.git("tag", "v3.58")
                    operation = lambda: release.plan(self.root)
                with self.assertRaises(ValueError):
                    operation()

    def test_packaged_version_and_notes_must_match_source(self):
        bundle = self.root / "Fixture.app"
        resources = bundle / "Contents/Resources"
        resources.mkdir(parents=True)
        info = bundle / "Contents/Info.plist"
        notes = resources / "CHANGELOG.md"
        for case in ("matching", "missing-notes", "stale-notes", "wrong-version"):
            with self.subTest(case=case):
                info.write_bytes((self.root / release.PLIST).read_bytes())
                notes.write_bytes((self.root / "CHANGELOG.md").read_bytes())
                if case == "matching":
                    release.verify_bundle(self.root, bundle)
                    continue
                if case == "missing-notes":
                    notes.unlink()
                elif case == "stale-notes":
                    notes.write_text("Old release")
                else:
                    info.write_bytes(plistlib.dumps({"CFBundleVersion": "3.51"}))
                with self.assertRaises((ValueError, FileNotFoundError)):
                    release.verify_bundle(self.root, bundle)

    def test_remote_tags_override_stale_local_tag_inventory_without_mutation(self):
        remote = self.root / "remote.git"
        self.git("clone", "--bare", str(self.root), str(remote))
        self.git("remote", "add", "origin", str(remote))
        self.git("tag", "v3.99")
        self.assertEqual(release.prepare(self.root, "2026-09-23", "origin"), "3.57")
        self.assertTrue(release.plan(self.root, "origin")["publish"])
        self.assertIn("3.99", release.tags(self.root))
        self.assertNotIn("3.57", release.tags(self.root, "origin"))

    def test_publication_stops_on_tag_conflict_or_release_failure(self):
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        gh = fake_bin / "gh"
        gh.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALL_LOG"\n'
                      'if [ "$1" = "$FAIL_COMMAND" ]; then exit 1; fi\n')
        gh.chmod(0o755)
        (self.root / "WhisperKiller-3.57.dmg").write_text("fixture artifact")
        (self.root / "release-notes.md").write_text("fixture notes")
        publisher = Path(__file__).parents[1] / "publish_release.sh"
        for failure, count in (("none", 2), ("api", 1), ("release", 2)):
            with self.subTest(failure=failure):
                log = self.root / f"calls-{failure}"
                env = dict(os.environ, PATH=f"{fake_bin}:{os.environ['PATH']}",
                           VERSION="3.57", GITHUB_SHA="a" * 40,
                           GITHUB_REPOSITORY="fixture/repo", RUNNER_TEMP=str(self.root),
                           CALL_LOG=str(log), FAIL_COMMAND=failure)
                result = subprocess.run(["bash", str(publisher)], cwd=self.root, env=env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, failure == "none")
                calls = log.read_text().splitlines()
                self.assertEqual(len(calls), count)
                self.assertIn("ref=refs/tags/v3.57", calls[0])
                self.assertIn("sha=" + "a" * 40, calls[0])
                if count == 2:
                    self.assertIn("--verify-tag", calls[1])
                    self.assertIn("--notes-file", calls[1])


if __name__ == "__main__":
    unittest.main()
