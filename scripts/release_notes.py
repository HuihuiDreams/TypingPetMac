"""Use the website's translated release notes in the native update feed."""

import json


LANGUAGES = ("ko", "en", "ja", "zh-Hans", "zh-Hant")


def localized_release_notes(root, version, *, required=False):
    path = root / "website/src/releases.json"
    if not path.is_file():
        if required:
            raise RuntimeError("Add website/src/releases.json before releasing.")
        return {}
    releases = json.loads(path.read_text())
    note = next((note for note in releases if note.get("version") == version), None)
    if note is None and not required:
        return {}
    result = {}
    for language in LANGUAGES:
        localized = (note or {}).get(language, {})
        title, items = localized.get("title"), localized.get("items")
        if (not isinstance(title, str) or not title.strip()
                or not isinstance(items, list) or not items
                or not all(isinstance(item, str) and item.strip() for item in items)):
            raise RuntimeError(f"Add {language} website notes for {version} in website/src/releases.json before releasing.")
        result[language] = title.strip() + "\n\n" + "\n".join("• " + item.strip() for item in items)
    return result
