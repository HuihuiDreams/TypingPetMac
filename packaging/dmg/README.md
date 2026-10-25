# Typing Pet DMG artwork

The installer uses the existing signed app and a real `/Applications` link, with 136pt Finder icons.
`settings.py` writes the Finder layout through dmgbuild 1.6.7, run in an isolated uv Python 3.12 environment.
The window reserves room for Finder tab/path/status bars that may be enabled globally.

`background.png` was generated with the built-in ImageGen tool on 2026-10-25.
It is background artwork only; the app and folder icons are real Finder items.
The build converts it to a 1520×880, 144 dpi TIFF for a 760×440 point Retina background.

The exact generation prompt is saved in `prompt.txt`.
The supplied Docker screenshot was a composition reference and is not included in the DMG.

```sh
./scripts/build_dmg.sh /absolute/path/TypingPet.app /absolute/path/TypingPetMac-v0.17.1-arm64-installer.dmg
```

The script verifies the original app, creates the image with this artwork/layout, signs and notarizes the
DMG, staples the ticket, mounts it read-only and compares its app to the source. It refuses to overwrite
an existing image/checksum. Use a new asset name when revising an already published installer.
The website prefers `-installer.dmg` when present, falling back to the earlier plain `.dmg` name.
