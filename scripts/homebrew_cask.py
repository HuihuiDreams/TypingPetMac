"""Generate the third-party cask; never execute or rewrite a downloaded Ruby file."""

import re

TAP_REPO = "ynifamily3/homebrew-tap"
CASK_PATH = "Casks/typing-pet.rb"


def render_cask(version, sha256):
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise RuntimeError("Invalid Homebrew version")
    if not re.fullmatch(r"[a-f0-9]{64}", sha256):
        raise RuntimeError("Invalid Homebrew SHA-256")
    return '''cask "typing-pet" do
  version "%s"
  sha256 "%s"

  url "https://github.com/ynifamily3/TypingPetMac/releases/download/v#{version}/TypingPetMac-v#{version}-arm64.zip"
  name "Typing Pet"
  desc "Desktop pet that reacts to keystrokes"
  homepage "https://github.com/ynifamily3/TypingPetMac"

  livecheck do
    url :url
    regex(/^v?(\\d+(?:\\.\\d+)+)$/i)
    strategy :github_releases do |json, regex|
      json.filter_map do |release|
        next if release["draft"]

        asset_name = "TypingPetMac-#{release["tag_name"]}-arm64.zip"
        next unless release["assets"]&.any? { |asset| asset["name"] == asset_name }

        release["tag_name"]&.[](regex, 1)
      end
    end
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :ventura

  app "TypingPet.app"

  zap trash: [
    "~/Library/Application Support/TypingPet",
    "~/Library/Preferences/ing.miel.typingpet.plist",
  ]

  caveats <<~EOS
    Open TypingPet from Applications and follow the Input Monitoring guide
    to enable pet reactions while using other apps.
  EOS
end
''' % (version, sha256)


def validate_cask_update(existing, replacement):
    if existing == replacement:
        return False
    if existing:
        previous = re.search(r'^  version "([0-9]+\.[0-9]+\.[0-9]+)"$', existing, re.MULTILINE)
        current = re.search(r'^  version "([0-9]+\.[0-9]+\.[0-9]+)"$', replacement, re.MULTILINE)
        if not previous or not current:
            raise RuntimeError("Cannot safely determine the existing Homebrew version")
        if tuple(map(int, current[1].split("."))) <= tuple(map(int, previous[1].split("."))):
            raise RuntimeError("Refusing to replace an equal or newer Homebrew release with different content")
    return True
