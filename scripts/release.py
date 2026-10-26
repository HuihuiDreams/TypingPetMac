#!/usr/bin/env python3
"""Local macOS release pipeline. Credentials stay in Keychain and the existing key directory."""

import argparse
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlparse
import zipfile

from homebrew_cask import CASK_PATH, TAP_REPO, render_cask, validate_cask_update
from release_notes import localized_release_notes

PROJECT = Path(__file__).resolve().parent.parent
BASE_URL = "https://pet.miel.ing/update"
FEED_URL = BASE_URL + "/production/latest.json"
SECRET_PATTERNS = [
    rb"-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----",
    rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})",
    rb"(?:AKIA|ASIA)[A-Z0-9]{16}",
    rb"AIza[A-Za-z0-9_-]{35}",
    rb"xox[baprs]-[A-Za-z0-9-]{20,}",
]


def fail(message):
    raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def version_tuple(version):
    if not isinstance(version, str) or not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        fail("version.json: version must be major.minor.patch (for example 0.14.4).")
    return tuple(map(int, version.split(".")))


def private_filename(name):
    path = Path(name)
    return (path.suffix.lower() in {".key", ".p12", ".pfx", ".p8", ".pem"}
            or path.name in {".env", "id_rsa", "id_ed25519"}
            or (path.name.startswith(".env.") and path.name != ".env.example"))


def inspect_bytes(name, data):
    if private_filename(name) or any(re.search(pattern, data) for pattern in SECRET_PATTERNS):
        fail(f"Possible private credential in {name}; value omitted. Review before releasing.")


def inspect_archive(path):
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if name.endswith("/"):
                continue
            data = archive.read(name)
            inspect_bytes(name, data)
            if "/Contents/MacOS/" in name and re.search(rb"/Users/[^/\x00\s]+/", data):
                fail("Release binary still contains a /Users/<name>/ build path.")


class Release:
    def __init__(self, root, options):
        self.root, self.options = root, options
        self.homebrew = getattr(options, "homebrew", False)
        if self.homebrew:
            options.github = True
        metadata = json.loads((root / "version.json").read_text())
        self.version, self.build = metadata["version"], metadata["build"]
        version_tuple(self.version)
        if type(self.build) is not int or self.build <= 0:
            fail("version.json: build must be a positive integer.")
        self.tag = "v" + self.version
        self.output = root / "dist/releases" / f"{self.tag}-{self.build}"
        self.app = self.output / "TypingPet.app"
        self.update_root = self.output / "update-server"
        self.manifest = self.update_root / "production/latest.json"
        self.asset = self.output / f"TypingPetMac-{self.tag}-arm64.zip"
        self.checksum = Path(str(self.asset) + ".sha256")
        self.ready = self.output / "ready.json"
        self.server = Path(os.environ.get("TYPINGPET_UPDATE_ROOT", str(Path.home() / "TypingPetUpdate"))).expanduser().resolve()
        self.env = dict(os.environ)
        self.log = None
        self.deployment_started = False
        self.website_enabled = ((root / "website/package.json").is_file()
                                and (Path.home() / "server/typing-pet-site/current").is_dir())

    def command(self, *args, capture=False):
        args = [str(arg) for arg in args]
        line = "$ " + shlex.join(args)
        print(line, flush=True)
        if self.log:
            self.log.write(line + "\n")
            self.log.flush()
        process = subprocess.Popen(args, cwd=self.root, env=self.env, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        output = []
        for line in process.stdout:
            if capture:
                output.append(line)
            else:
                print(line, end="", flush=True)
            if self.log:
                self.log.write(line)
                self.log.flush()
        if process.wait():
            # Captured output can contain account details; show it only for normal commands.
            fail(f"Command failed ({process.returncode}): {shlex.join(args)}")
        return "".join(output).strip()

    def script(self, name, *args):
        return self.command(self.root / "scripts" / name, *args)

    def snapshot(self):
        paths = self.command("git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", capture=True)
        checksum = hashlib.sha256()
        key_dir = Path(self.env.get("TYPINGPET_UPDATE_KEY_DIR", str(Path.home() / ".config/typingpet/update-keys"))).expanduser()
        key_file = key_dir / "production.key"
        private_key = key_file.read_bytes().strip() if key_file.is_file() else b""
        for name in sorted(set(paths.split("\0")) - {""}):
            path = self.root / name
            if not path.is_file():
                fail(f"Missing source file: {name}")
            data = path.read_bytes()
            inspect_bytes(name, data)
            if private_key and private_key in data:
                fail(f"The current production private key appears in {name}; value omitted.")
            checksum.update(name.encode() + b"\0" + hashlib.sha256(data).digest())
        return checksum.hexdigest()

    def preflight(self):
        if sys.platform != "darwin" or platform.machine() != "arm64":
            fail("Release on an Apple Silicon Mac.")
        for tool in ["swift", "xcrun", "codesign", "security", "spctl", "ditto", "curl", "git"] + (["gh"] if self.options.github else []):
            if not shutil.which(tool):
                fail(f"Missing command: {tool}")
        dirty = self.command("git", "status", "--porcelain", capture=True)
        if dirty and (not self.options.allow_dirty or self.options.github):
            fail("Commit the source, version.json and CHANGELOG.md first. --allow-dirty is available for local-only releases.")
        self.commit = self.command("git", "rev-parse", "HEAD", capture=True)
        self.source = self.snapshot()
        sections = re.split(r"(?m)^## ", (self.root / "CHANGELOG.md").read_text())
        self.notes = next((section.partition("\n")[2].strip() for section in sections
                           if section.startswith(self.version + " ")), "")
        if not self.notes:
            fail(f"Add a nonempty '## {self.version} - YYYY-MM-DD' section to CHANGELOG.md.")
        identities = self.command("security", "find-identity", "-v", "-p", "codesigning", capture=True)
        identities = re.findall(r'"(Developer ID Application:[^"]+)"', identities)
        identity = self.env.get("CODE_SIGN_IDENTITY")
        if not identity and len(identities) == 1:
            identity = identities[0]
        if identity not in identities:
            fail("Select a valid Developer ID Application name with CODE_SIGN_IDENTITY (required when several exist).")
        team = re.search(r"\(([A-Z0-9]{10})\)$", identity).group(1)
        if self.env.get("TYPINGPET_TEAM_ID", team) != team:
            fail("TYPINGPET_TEAM_ID differs from the selected Developer ID certificate.")
        self.env.update(CODE_SIGN_IDENTITY=identity, TYPINGPET_TEAM_ID=team,
                        TYPINGPET_BUILD_CHANNEL="production", SWIFT_BUILD_CONFIGURATION="release",
                        TYPINGPET_VERSION=self.version, TYPINGPET_BUILD=str(self.build), UPDATE_NOTES=self.notes)
        key_dir = Path(self.env.get("TYPINGPET_UPDATE_KEY_DIR", str(Path.home() / ".config/typingpet/update-keys"))).expanduser().resolve()
        for name in ["production.key", "production.pub"]:
            if not (key_dir / name).is_file():
                fail(f"Restore the original {key_dir / name}; never generate a replacement release key.")
        self.env["TYPINGPET_UPDATE_KEY_DIR"] = str(key_dir)
        if not self.server.is_dir():
            fail(f"Update server root does not exist: {self.server}")
        self.previous = json.loads((self.server / "production/latest.json").read_text())
        public = json.loads(self.command("curl", "--fail", "--silent", "--show-error", "--connect-timeout", "10",
                                         "--max-time", "30", FEED_URL, capture=True))
        if public != self.previous:
            fail("Local and public feeds differ. Inspect the server before releasing.")
        if self.options.resume:
            self.validate_ready()
            prepared = json.loads(self.manifest.read_text())
            if self.build < self.previous["build"] or (self.build == self.previous["build"] and prepared != self.previous):
                fail("A newer or different update is already published.")
        elif self.build <= self.previous["build"] or version_tuple(self.version) <= version_tuple(self.previous["version"]):
            fail(f"Increase both version and build above {self.previous['version']} ({self.previous['build']}) in version.json.")
        elif self.output.exists():
            fail(f"Release directory already exists: {self.output}. Use --resume for a prepared release, or inspect the failed attempt first.")
        self.check_website_notes()
        if self.options.github:
            self.repo = self.command("gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner", capture=True)
            remote_commit = self.command("gh", "api", f"repos/{self.repo}/commits/{self.commit}", "--jq", ".sha", capture=True)
            if remote_commit != self.commit:
                fail("Push the release commit before publishing a GitHub release.")
            self.check_github_tag()
        if self.homebrew:
            tap = json.loads(self.command("gh", "api", f"repos/{TAP_REPO}", capture=True))
            if tap["private"] or not tap.get("permissions", {}).get("push"):
                fail("Homebrew tap must be public and writable by the active GitHub account.")

    def check_website_notes(self):
        localized_release_notes(self.root, self.version, required=True)

    def publish_homebrew(self):
        # Only reference the exact bytes of the now-public GitHub asset.
        release = json.loads(self.command("gh", "release", "view", self.tag, "--repo", self.repo,
                                         "--json", "isDraft,assets", capture=True))
        if release["isDraft"] or not any(asset["name"] == self.asset.name for asset in release["assets"]):
            fail("Publish the GitHub ZIP before updating Homebrew.")
        with tempfile.TemporaryDirectory(prefix="typingpet-homebrew-verify-") as directory:
            for asset in [self.asset, self.checksum]:
                self.command("gh", "release", "download", self.tag, "--repo", self.repo,
                             "--pattern", asset.name, "--dir", directory)
                if digest(Path(directory) / asset.name) != digest(asset):
                    fail("Published GitHub asset differs; Homebrew was not updated.")
        content = render_cask(self.version, digest(self.asset))
        (self.output / "typing-pet.rb").write_text(content)
        tree = json.loads(self.command("gh", "api", f"repos/{TAP_REPO}/git/trees/main?recursive=1", capture=True))
        if tree.get("truncated"):
            fail("Homebrew tap tree is truncated; inspect the tap before updating.")
        entry = next((entry for entry in tree["tree"] if entry["path"] == CASK_PATH), None)
        existing = ""
        if entry:
            blob = json.loads(self.command("gh", "api", f"repos/{TAP_REPO}/git/blobs/{entry['sha']}", capture=True))
            existing = base64.b64decode(blob["content"], validate=False).decode()
        if not validate_cask_update(existing, content):
            print("Homebrew cask is already published with identical content.")
            return
        payload = {"message": f"Update Typing Pet to {self.version}", "branch": "main",
                   "content": base64.b64encode(content.encode()).decode()}
        if entry:
            payload["sha"] = entry["sha"]
        with tempfile.TemporaryDirectory(prefix="typingpet-homebrew-request-") as directory:
            body = Path(directory) / "request.json"
            body.write_text(json.dumps(payload))
            self.command("gh", "api", "--method", "PUT", f"repos/{TAP_REPO}/contents/{CASK_PATH}",
                         "--input", body, capture=True)
        published = json.loads(self.command("gh", "api", f"repos/{TAP_REPO}/contents/{CASK_PATH}?ref=main", capture=True))
        if base64.b64decode(published["content"]).decode() != content:
            fail("Homebrew cask changed during publication; inspect the tap.")
        print(f"Homebrew published: https://github.com/{TAP_REPO}/blob/main/{CASK_PATH}")

    def check_github_tag(self):
        refs = json.loads(self.command("gh", "api", f"repos/{self.repo}/git/matching-refs/tags/{self.tag}", capture=True))
        ref = next((ref for ref in refs if ref["ref"] == f"refs/tags/{self.tag}"), None)
        if ref:
            target = ref["object"]
            for _ in range(10):
                if target["type"] != "tag":
                    break
                tag = json.loads(self.command("gh", "api", f"repos/{self.repo}/git/tags/{target['sha']}", capture=True))
                target = tag["object"]
            if target["type"] != "commit" or target["sha"] != self.commit:
                fail("GitHub tag points to another commit. Existing tags are never moved.")

    def validate_ready(self):
        if not self.ready.is_file():
            fail("No prepared release. --resume requires a completed ready.json; inspect release.log and notary-result.json first.")
        saved = json.loads(self.ready.read_text())
        if saved["source"] != self.source or saved["commit"] != self.commit:
            fail("Source changed since packaging. Use a new version/build instead of resuming.")
        for name, expected in saved["files"].items():
            path = self.output / name
            if not path.is_file() or digest(path) != expected:
                fail(f"Prepared artifact changed: {name}")
        inspect_archive(self.asset)

    def prepare(self):
        self.command("swift", self.root / "scripts/update_keys.swift", "check", "production")
        previous_archive = self.server / "production" / Path(urlparse(self.previous["url"]).path).name
        self.command("swift", self.root / "scripts/update_keys.swift", "verify", "production",
                     previous_archive, self.previous["signature"])
        self.command("xcrun", "notarytool", "history", "--keychain-profile",
                     self.env.get("NOTARY_KEYCHAIN_PROFILE", "typingpet-notary"), "--output-format", "json", capture=True)
        self.command("swift", "test")
        self.script("check_todo.sh")
        self.script("check_publish_update.sh")
        self.script("build_app.sh", self.output)
        self.env["NOTARY_RESULT_PATH"] = str(self.output / "notary-result.json")
        self.script("notarize_release.sh", self.app, self.output / "notarized.zip")
        self.script("publish_update.sh", "production", self.app, self.update_root, BASE_URL)
        manifest = json.loads(self.manifest.read_text())
        archive = self.manifest.parent / Path(urlparse(manifest["url"]).path).name
        shutil.copyfile(archive, self.asset)
        inspect_archive(self.asset)
        self.checksum.write_text(f"{digest(self.asset)}  {self.asset.name}\n")
        (self.output / "release-notes.md").write_text(self.notes + "\n")
        if self.snapshot() != self.source:
            fail("Source changed during release preparation. Nothing was deployed; start with a new version/build.")
        files = [self.asset, self.checksum, self.manifest, archive, self.output / "release-notes.md"]
        self.ready.write_text(json.dumps({"version": self.version, "build": self.build, "source": self.source,
                                         "commit": self.commit, "files": {str(p.relative_to(self.output)): digest(p) for p in files}}, indent=2) + "\n")

    def github_draft(self):
        # List instead of swallowing a failed 'view': network/auth failures must not look like an absent release.
        pages = json.loads(self.command("gh", "api", "--paginate", "--slurp", f"repos/{self.repo}/releases", capture=True))
        existing = [release for page in pages for release in page]
        release = next((r for r in existing if r["tag_name"] == self.tag), None)
        if release:
            if release["target_commitish"] != self.commit:
                fail("GitHub release tag already targets another commit. Inspect it manually.")
            if not release["draft"]:
                with tempfile.TemporaryDirectory(prefix="typingpet-github-verify-") as directory:
                    for asset in [self.asset, self.checksum]:
                        self.command("gh", "release", "download", self.tag, "--repo", self.repo,
                                     "--pattern", asset.name, "--dir", directory)
                        if digest(Path(directory) / asset.name) != digest(asset):
                            fail("Published GitHub asset differs. Published releases are never overwritten.")
                return False
            self.command("gh", "release", "upload", self.tag, self.asset, self.checksum, "--repo", self.repo, "--clobber")
        else:
            self.command("gh", "release", "create", self.tag, self.asset, self.checksum, "--repo", self.repo,
                         "--target", self.commit, "--title", f"TypingPet {self.tag}", "--notes-file",
                         self.output / "release-notes.md", "--draft", "--prerelease")
        return True

    def execute(self):
        self.preflight()
        print(f"\nRelease: {self.version} ({self.build})\nArtifacts: {self.output}\nServer: {self.server}")
        print("Tests → release build + Developer ID → notarization + staple → signed ZIP → deploy + URL verification")
        if self.options.github:
            print("GitHub: draft with ZIP/checksum → publish prerelease after update server verification")
        if self.homebrew:
            print(f"Homebrew: verify public GitHub ZIP → update {TAP_REPO}/{CASK_PATH}")
        if self.options.github and self.website_enabled:
            print("Website: verify the public release → refresh all localized pages and latest download redirect")
        if self.options.dry_run:
            print("Dry run complete. No builds, notarization submissions or publication performed.")
            return
        # One pipeline per checkout; deploy_update.sh also locks the shared server destination.
        lock_path = self.root / "dist/.release.lock"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                fail("Another release is running in this checkout.")
            self.output.mkdir(parents=True, exist_ok=self.options.resume)
            with (self.output / "release.log").open("a", buffering=1) as self.log:
                if not self.options.resume:
                    (self.output / "previous-latest.json").write_text(json.dumps(self.previous, indent=2) + "\n")
                    self.prepare()
                if self.options.prepare_only:
                    print("Prepared; nothing published. Run the same command with --resume to deploy.")
                    return
                self.validate_ready()
                draft = self.github_draft() if self.options.github else False
                if self.options.github:
                    self.check_github_tag()
                self.deployment_started = True
                self.script("deploy_update.sh", "production", self.app, self.server, self.update_root)
                if draft:
                    self.command("gh", "release", "edit", self.tag, "--repo", self.repo, "--draft=false")
                if self.homebrew:
                    self.publish_homebrew()
                if self.options.github and self.website_enabled:
                    self.script("deploy_website.sh")
                (self.output / "complete.json").write_text(json.dumps({"version": self.version, "build": self.build,
                    "feed": FEED_URL, "github": f"https://github.com/{self.repo}/releases/tag/{self.tag}" if self.options.github else None,
                    "homebrew": f"https://github.com/{TAP_REPO}/blob/main/{CASK_PATH}" if self.homebrew else None}, indent=2) + "\n")
        print(f"Released {self.version} ({self.build}). Artifacts and log: {self.output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="Read-only preflight and plan; no build, submission, or publication")
    parser.add_argument("--prepare-only", action="store_true", help="Test, build, notarize and package without publishing")
    parser.add_argument("--resume", action="store_true", help="Deploy the saved, unchanged prepared artifacts without rebuilding")
    parser.add_argument("--github", action="store_true", help="Also publish a GitHub prerelease with ZIP and SHA-256")
    parser.add_argument("--homebrew", action="store_true", help="Also update the Homebrew cask after publishing GitHub (implies --github)")
    parser.add_argument("--allow-dirty", action="store_true", help="Allow uncommitted sources for local-only releases; unavailable with --github")
    options = parser.parse_args()
    release = None
    try:
        release = Release(PROJECT, options)
        release.execute()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        if release and release.deployment_started:
            print("Deployment started; the feed may already be live. Inspect the server and retry the unchanged artifacts with --resume.", file=sys.stderr)
        if release and release.output.exists():
            print(f"Saved release artifacts and log: {release.output}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Release interrupted. Inspect the log and notary submission before retrying.", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
