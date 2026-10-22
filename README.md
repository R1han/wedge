# Wedge

Wedge is a file-conversion command-line tool for macOS. It converts images, documents, audio, video, archives and PDFs from one format to another with a single command, using native macOS frameworks where possible and well-known tools where not.

## Install

```sh
brew tap R1han/wedge
brew trust r1han/wedge
brew install wedge
```

Installing through Homebrew also installs the external converter tools (`pandoc` and `ffmpeg`).

The binary is built as a universal (arm64 + x86_64) executable by CI on each release. Builds made locally are for the architecture of the machine that built them (for example Apple Silicon).

## Usage

```sh
wedge list                                  # show every supported conversion
wedge convert <input> --to <format>         # convert a file
wedge doctor                                # check which converter tools are available
```

Options for `convert`:

| Option | Meaning |
| --- | --- |
| `--to <fmt>` | Target format (required). Use `--to dir` to extract an archive into a directory |
| `--out <dir>` | Output directory (defaults to next to the input) |
| `--quality <n>` | Output quality for lossy image formats, from 0 to 1 |
| `--max-dim <px>` | Scale images so the longest side is at most this size |
| `--strip-metadata` | Remove metadata (such as EXIF) from the output |
| `--force` | Overwrite an existing output file |

## App (menu-bar)

Wedge also ships as a macOS menu-bar app. It lives in the menu bar and has no Dock icon. Open it from the menu-bar icon with Open Shelf.

The shelf is a floating window for converting files without the command line:

- Drop files onto it, or choose Add Files...
- Pick the target format. Only formats available for every file on the shelf are offered.
- Set options if you need them: output folder, image quality, maximum dimension, strip metadata.
- Choose Convert. Each file shows its progress, and Reveal in Finder opens the converted files.

The app never overwrites an existing file unless "Replace existing files" is turned on.

Settings lets you choose the default format, the output folder (next to the originals by default) and whether Wedge opens when you log in. The Tools submenu in the menu-bar menu shows whether `pandoc` and `ffmpeg` are found.

To build and run it from source you need full Xcode (not only the Command Line Tools) and XcodeGen:

```sh
brew install xcodegen
bash scripts/build-app.sh
open build/DerivedData/Build/Products/Debug/Wedge.app
```

To run the app's tests:

```sh
bash scripts/test-app.sh
```

The app is ad-hoc signed and is not yet distributed through Homebrew; a cask will come later. The radial Action Wheel is planned and not yet available.

## Converters

| Category | Engine | Notes |
| --- | --- | --- |
| Images | Native macOS image frameworks | Format conversion, quality, resizing, metadata stripping |
| Documents | `pandoc` | Conversions between text and document formats |
| Audio and video | `ffmpeg` | Audio and video format conversion |
| Archives | Built in | Archive format conversion |
| PDF | PDFKit (native) | No external tool required |

Run `wedge list` for the exact input and output formats supported in your build.

## External tools

Document conversion needs `pandoc`, and audio and video conversion needs `ffmpeg`. Homebrew installs both as dependencies of the `wedge` formula. If you build from source, install them yourself:

```sh
brew install pandoc ffmpeg
```

`wedge doctor` reports whether each tool is found, so you can see what is missing before a conversion fails.

## Build from source

```sh
swift build
./scripts/test.sh
```

This builds the command-line tool. The menu-bar app is built separately; see App (menu-bar).

## License

MIT. See [LICENSE](LICENSE).
