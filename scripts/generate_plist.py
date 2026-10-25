import plistlib
import sys

def main():
    path, name, executable, bundle_id, display, channel, version, build, team_id, public_key = sys.argv[1:]
    info = {
        "CFBundleDevelopmentRegion": "zh-Hans",
        "CFBundleLocalizations": ["zh-Hans", "zh-Hant", "en", "ja", "ko"],
        "CFBundleDisplayName": display,
        "CFBundleExecutable": executable,
        "CFBundleIdentifier": bundle_id,
        "CFBundleIconFile": "AppIcon",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": name,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "LSMinimumSystemVersion": "13.0",
        "LSUIElement": True,
        "TypingPetBuildChannel": channel,
        "NSHumanReadableCopyright": "Personal macOS build",
        "NSInputMonitoringUsageDescription": "TypingPet 需要输入监控权限，以便在敲击键盘时实时切换宠物的互动表情。",
    }
    if team_id:
        info["TypingPetTeamIdentifier"] = team_id
    if public_key:
        info["TypingPetUpdatePublicKey"] = public_key
    if channel == "development":
        # Lets Dev builds read an update feed from a local http server.
        info["NSAppTransportSecurity"] = {"NSAllowsLocalNetworking": True}
    with open(path, "wb") as file:
        plistlib.dump(info, file)

if __name__ == "__main__":
    main()
