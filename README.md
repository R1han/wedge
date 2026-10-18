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
| `--to <fmt>` | Target format (required) |
| `--out <path>` | Output path (defaults to the input name with the new extension) |
| `--quality <n>` | Output quality for lossy image formats |
| `--max-dim <px>` | Scale images so the longest side is at most this size |
| `--strip-metadata` | Remove metadata (such as EXIF) from the output |
| `--force` | Overwrite an existing output file |

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

## License

MIT. See [LICENSE](LICENSE).
