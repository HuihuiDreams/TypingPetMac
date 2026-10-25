# Typing Pet for macOS

[한국어](README.md) · [English](README.en.md)

<p align="center">
  <a href="https://typing-pet.miel.ing/"><strong>Visit the Typing Pet website</strong></a>
</p>

The [website](https://typing-pet.miel.ing/) has the product overview, installation instructions, and release notes.

## Development

Requires an Apple Silicon Mac, macOS 13 or later, Swift 6, and Xcode Command Line Tools. The development app keeps its settings and data separate from the installed app.

```sh
./scripts/run_dev.sh
```

Run tests and build the app:

```sh
swift test
./scripts/build_app.sh
```

See the [development guide](developer-notes/development.md) for details.

## Project notes

This unofficial macOS project is a new implementation inspired by [Typing Pet for Windows](https://github.com/swoonqx/TypingPet). It does not include the original project's source code or image assets.

- Source code: [MIT](LICENSE)
- Built-in keyboard cat image: [CC0 1.0](ASSET_LICENSE.md)

The built-in image is an AI-generated placeholder created for this repository. Images imported by users remain subject to their original creators' rights.
