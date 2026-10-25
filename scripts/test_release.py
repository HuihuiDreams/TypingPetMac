"""Pipeline guard tests; never contact Apple, GitHub or the production server."""

import argparse
import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from unittest.mock import patch
import zipfile

from release import Release, digest, inspect_archive, inspect_bytes, version_tuple
from homebrew_cask import render_cask, validate_cask_update
from release_notes import LANGUAGES, localized_release_notes


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="typingpet-release-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "version.json").write_text('{"version":"0.14.4","build":24}')
        (self.root / "CHANGELOG.md").write_text("# Changelog\n\n## 0.14.4 - 2026-10-24\n\n- A release fixture.\n")
        (self.root / "website/src").mkdir(parents=True)
        self.translations = {language: {"title": f"{language} title", "items": [f"{language} change"]} for language in LANGUAGES}
        self.notes_path = self.root / "website/src/releases.json"
        self.notes_path.write_text(json.dumps([{"version": "0.14.4", **self.translations}]))
        self.previous = {"version": "0.14.3", "build": 23, "url": "https://pet.miel.ing/update/production/old.zip", "signature": "fixture"}
        self.server = self.root / "server"
        (self.server / "production").mkdir(parents=True)
        (self.server / "production/latest.json").write_text(json.dumps(self.previous))
        keys = self.root / "keys"
        keys.mkdir()
        for name in ["production.key", "production.pub"]:
            (keys / name).write_text("fixture only")
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, {"TYPINGPET_UPDATE_ROOT": str(self.server), "TYPINGPET_UPDATE_KEY_DIR": str(keys),
                                "CODE_SIGN_IDENTITY": "Developer ID Application: Fixture (AAAAAAAAAA)", "TYPINGPET_TEAM_ID": "AAAAAAAAAA"}).start()
        patch("release.sys.platform", "darwin").start()
        patch("release.platform.machine", return_value="arm64").start()
        patch("release.shutil.which", return_value="fixture-command").start()
        self.commands = []

    def make_release(self, **changes):
        flags = dict(dry_run=False, prepare_only=False, resume=False, github=False, allow_dirty=False)
        flags.update(changes)
        release = Release(self.root, argparse.Namespace(**flags))
        release.command = self.read_command
        return release

    def read_command(self, *args, **kwargs):
        command = tuple(map(str, args))
        self.commands.append(command)
        if command == ("git", "status", "--porcelain"):
            return ""
        if command == ("git", "rev-parse", "HEAD"):
            return "a" * 40
        if command[:2] == ("git", "ls-files"):
            return "version.json\0CHANGELOG.md\0website/src/releases.json\0"
        if command[0] == "security":
            return '1) 012345 "Developer ID Application: Fixture (AAAAAAAAAA)"'
        if command[0] == "curl":
            return json.dumps(self.previous)
        raise AssertionError(f"Unexpected command: {command}")

    def save_ready(self, release):
        release.preflight()
        release.output.mkdir(parents=True)
        release.manifest.parent.mkdir(parents=True)
        release.manifest.write_text('{"version":"0.14.4","build":24}')
        with zipfile.ZipFile(release.asset, "w") as archive:
            archive.writestr("TypingPet.app/Contents/MacOS/TypingPet", b"fixture executable")
        files = [release.manifest, release.asset]
        release.ready.write_text(json.dumps({"source": release.source, "commit": release.commit,
            "files": {str(p.relative_to(release.output)): digest(p) for p in files}}))

    def test_dry_run_is_read_only(self):
        release = self.make_release(dry_run=True)
        with contextlib.redirect_stdout(io.StringIO()):
            release.execute()
        self.assertFalse((self.root / "dist").exists())
        self.assertTrue(all(c[0] in {"git", "security", "curl"} for c in self.commands))

    def test_same_or_lower_release_stops_before_build(self):
        for version, build in [("0.14.3", 23), ("0.14.4", 23), ("0.14.2", 24)]:
            (self.root / "version.json").write_text(json.dumps(dict(version=version, build=build)))
            (self.root / "CHANGELOG.md").write_text(f"## {version} - 2026-10-24\n\n- Fixture\n")
            release = self.make_release()
            with self.assertRaisesRegex(RuntimeError, "Increase both"):
                release.preflight()
            self.assertFalse(release.output.exists())

    def test_missing_changelog_stops_before_signing(self):
        (self.root / "CHANGELOG.md").write_text("# Changelog\n")
        with self.assertRaisesRegex(RuntimeError, "nonempty"):
            self.make_release().preflight()
        self.assertFalse(any(c[0] in {"security", "xcrun"} for c in self.commands))

    def test_failed_tests_do_not_build_notarize_or_deploy(self):
        release = self.make_release()
        release.preflight()
        real_command = release.command

        def command(*args, **kwargs):
            cmd = tuple(map(str, args))
            if cmd[:2] == ("swift", "test"):
                raise RuntimeError("test failure")
            if cmd[0] in {"swift", "xcrun"}:
                self.commands.append(cmd)
                return ""
            return real_command(*args, **kwargs)

        release.command = command
        with self.assertRaisesRegex(RuntimeError, "test failure"):
            release.execute()
        self.assertFalse(release.app.exists())
        self.assertFalse(release.ready.exists())
        self.assertFalse(any("submit" in c or any("deploy_update.sh" in a for a in c) for c in self.commands))
        self.assertEqual(json.loads((self.server / "production/latest.json").read_text()), self.previous)

    def test_resume_refuses_changed_archive(self):
        release = self.make_release()
        self.save_ready(release)
        release.asset.write_bytes(b"changed after signing")
        with self.assertRaisesRegex(RuntimeError, "artifact changed"):
            release.validate_ready()

    def test_resume_refuses_changed_source(self):
        release = self.make_release()
        self.save_ready(release)
        (self.root / "CHANGELOG.md").write_text("changed source")
        release.source = release.snapshot()
        with self.assertRaisesRegex(RuntimeError, "Source changed"):
            release.validate_ready()

    def test_archive_rejects_private_files_and_home_paths(self):
        archive_path = self.root / "fixture.zip"
        for name, data in [("TypingPet.app/production.key", b"fixture"),
                           ("TypingPet.app/Contents/MacOS/TypingPet", b"debug /Users/fixture/project/file.swift")]:
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(name, data)
            with self.assertRaises(RuntimeError):
                inspect_archive(archive_path)

    def test_secret_report_does_not_include_value(self):
        token = b"ghp_" + b"A" * 36
        with self.assertRaises(RuntimeError) as error:
            inspect_bytes("fixture.swift", token)
        self.assertNotIn(token.decode(), str(error.exception))

    def test_invalid_version_rejected(self):
        for version in ["../0.14.4", "0.14.4-beta", "01.14.4", "0.14", 14]:
            with self.assertRaises(RuntimeError):
                version_tuple(version)

    def test_github_tag_cannot_point_to_another_commit(self):
        release = self.make_release(github=True)
        release.repo, release.commit = "fixture/repo", "a" * 40
        release.command = lambda *a, **kw: json.dumps([{
            "ref": "refs/tags/v0.14.4", "object": {"type": "commit", "sha": "b" * 40}}])
        with self.assertRaisesRegex(RuntimeError, "another commit"):
            release.check_github_tag()

    def test_annotated_github_tag_resolves_to_source_commit(self):
        release = self.make_release(github=True)
        release.repo, release.commit = "fixture/repo", "a" * 40

        def command(*args, **kwargs):
            if "matching-refs" in str(args[-1]):
                return json.dumps([{"ref": "refs/tags/v0.14.4", "object": {"type": "tag", "sha": "b" * 40}}])
            return json.dumps({"object": {"type": "commit", "sha": release.commit}})

        release.command = command
        release.check_github_tag()

    def test_current_private_key_in_source_is_rejected_without_value(self):
        (self.root / "CHANGELOG.md").write_text("fixture only")
        with self.assertRaisesRegex(RuntimeError, "current production private key") as error:
            self.make_release().snapshot()
        self.assertNotIn("fixture only", str(error.exception))

    def test_homebrew_implies_github(self):
        release = self.make_release(homebrew=True)
        self.assertTrue(release.options.github)

    def test_website_requires_all_languages_before_publication(self):
        directory = self.root / "website/src"
        directory.mkdir(parents=True, exist_ok=True)
        languages = ["ko", "en", "ja", "zh-Hans", "zh-Hant"]
        (directory / "locales.json").write_text(json.dumps(dict.fromkeys(languages, {})))
        notes = [{"version": "0.14.4", "ko": {"title": "Fixture", "items": ["Fixture"]}}]
        (directory / "releases.json").write_text(json.dumps(notes))
        release = self.make_release()
        with self.assertRaisesRegex(RuntimeError, "en website notes"):
            release.check_website_notes()
        for language in languages[1:]:
            with self.assertRaisesRegex(RuntimeError, f"{language} website notes"):
                release.check_website_notes()
            notes[0][language] = {"title": "Fixture", "items": ["Fixture"]}
            (directory / "releases.json").write_text(json.dumps(notes))
        release.check_website_notes()

    def test_website_rejects_notes_for_another_version(self):
        directory = self.root / "website/src"
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "locales.json").write_text('{"ko":{}}')
        (directory / "releases.json").write_text('[{"version":"0.14.3"}]')
        with self.assertRaisesRegex(RuntimeError, "ko website notes for 0.14.4"):
            self.make_release().check_website_notes()

    def test_update_notes_select_matching_version_and_keep_all_translations(self):
        self.notes_path.write_text(json.dumps([
            {"version": "0.14.5", **{language: {"title": "Future", "items": ["Future"]} for language in LANGUAGES}},
            {"version": "0.14.4", **self.translations},
        ]))
        notes = localized_release_notes(self.root, "0.14.4", required=True)
        self.assertEqual(set(notes), set(LANGUAGES))
        for language in LANGUAGES:
            self.assertEqual(notes[language], f"{language} title\n\n• {language} change")

    def test_missing_update_notes_remain_optional_for_old_development_versions(self):
        self.assertEqual(localized_release_notes(self.root, "0.13.0"), {})
        with self.assertRaisesRegex(RuntimeError, "ko website notes for 0.13.0"):
            localized_release_notes(self.root, "0.13.0", required=True)

    def test_blank_update_translation_stops_even_without_github_or_website_deployment(self):
        self.translations["ja"]["items"] = [" "]
        self.notes_path.write_text(json.dumps([{"version": "0.14.4", **self.translations}]))
        with self.assertRaisesRegex(RuntimeError, "ja website notes"):
            self.make_release(github=False).preflight()
        self.assertFalse((self.root / "dist").exists())

    def test_update_notes_preserve_unicode_and_literal_format_tokens(self):
        self.translations["ko"] = {"title": "업데이트", "items": ["할 일 %1$@", "이미지 🐈"]}
        self.notes_path.write_text(json.dumps([{"version": "0.14.4", **self.translations}]))
        self.assertEqual(localized_release_notes(self.root, "0.14.4")["ko"], "업데이트\n\n• 할 일 %1$@\n• 이미지 🐈")

    def test_homebrew_refuses_draft_before_mutating_tap(self):
        release = self.make_release(homebrew=True)
        release.repo = "fixture/repo"
        release.command = lambda *args, **kwargs: json.dumps({"isDraft": True, "assets": []})
        with self.assertRaisesRegex(RuntimeError, "Publish the GitHub ZIP"):
            release.publish_homebrew()

    def test_homebrew_refuses_changed_published_zip(self):
        release = self.make_release(homebrew=True)
        release.repo = "fixture/repo"
        release.output.mkdir(parents=True)
        release.asset.write_bytes(b"original fixture")
        release.checksum.write_text("fixture checksum")
        commands = []

        def command(*args, **kwargs):
            commands.append(args)
            if args[:3] == ("gh", "release", "view"):
                return json.dumps({"isDraft": False, "assets": [{"name": release.asset.name}]})
            if args[:3] == ("gh", "release", "download"):
                directory = Path(args[args.index("--dir") + 1])
                (directory / release.asset.name).write_bytes(b"different public fixture")
                return ""
            self.fail(f"Unexpected mutation: {args}")

        release.command = command
        with self.assertRaisesRegex(RuntimeError, "Homebrew was not updated"):
            release.publish_homebrew()
        self.assertFalse(any("PUT" in command for command in commands))


class HomebrewTests(unittest.TestCase):
    def test_rejects_invalid_version_and_checksum_before_rendering_ruby(self):
        for version, sha in [("../1.0.0", "a" * 64), ("1.0.0", "no_check"), ("01.0.0", "a" * 64)]:
            with self.assertRaises(RuntimeError):
                render_cask(version, sha)

    def test_cask_update_is_idempotent_and_cannot_downgrade_or_replace_release(self):
        existing = render_cask("0.15.0", "a" * 64)
        self.assertFalse(validate_cask_update(existing, existing))
        self.assertTrue(validate_cask_update("", existing))
        self.assertTrue(validate_cask_update(existing, render_cask("0.16.0", "b" * 64)))
        for version in ["0.14.4", "0.15.0"]:
            with self.assertRaisesRegex(RuntimeError, "equal or newer"):
                validate_cask_update(existing, render_cask(version, "b" * 64))
        with self.assertRaisesRegex(RuntimeError, "safely determine"):
            validate_cask_update("unknown cask format", existing)


@unittest.skipUnless(sys.platform == "darwin", "Notarization helper runs on macOS")
class NotarizationTests(unittest.TestCase):
    def test_only_accepted_submission_can_be_stapled(self):
        script = Path(__file__).parent / "notarize_release.sh"
        for status in ["Accepted", "Invalid", "In Progress"]:
            with self.subTest(status=status), tempfile.TemporaryDirectory(prefix="typingpet-notary-test-") as directory:
                root = Path(directory)
                app = root / "TypingPet.app"
                app.mkdir()
                events = root / "events"
                stub = """#!/usr/bin/env python3
import json,os,pathlib,sys
tool=pathlib.Path(sys.argv[0]).name
with open(os.environ['FIXTURE_EVENTS'],'a') as log:log.write(tool+' '+ ' '.join(sys.argv[1:])+'\\n')
if tool=='codesign':print('Authority=Developer ID Application: Fixture (AAAAAAAAAA)',file=sys.stderr)
if tool=='ditto':pathlib.Path(sys.argv[-1]).touch()
if tool=='xcrun' and sys.argv[1:3]==['notarytool','submit']:
 print(json.dumps({'id':'fixture-submission','status':os.environ['FIXTURE_STATUS']}))
"""
                for name in ["codesign", "ditto", "xcrun", "spctl"]:
                    path = root / name
                    path.write_text(stub)
                    path.chmod(0o755)
                env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}", FIXTURE_EVENTS=str(events), FIXTURE_STATUS=status,
                           NOTARY_RESULT_PATH=str(root / "result.json"))
                result = subprocess.run(["zsh", str(script), str(app), str(root / "release.zip")],
                                        env=env, text=True, capture_output=True)
                accepted = status == "Accepted"
                self.assertEqual(result.returncode == 0, accepted, result.stdout + result.stderr)
                self.assertEqual("stapler staple" in events.read_text(), accepted)
                self.assertEqual((root / "release.zip").exists(), accepted)


if __name__ == "__main__":
    unittest.main()
