# MDF (Modern Document Format)

MDF is an experimental, security-first, chunked binary document container with a Zig reference implementation.

## What’s implemented in this repo

### MDF container prototype
- A deterministic chunked container with CRC32 integrity per chunk and an explicit “no-execution” verifier policy.
- Chunk types used by the prototype: `META` (JSON metadata) and `DATA` (raw bytes).

### MDF paged document mode + tools
- Chunk types: `DOCM` (manifest JSON), `PAGE` (page JSON), `IMG_` (PNG bytes prefixed with an image id).
- `mdf demo`: generates a high-detail demo document (no external dependencies).
- `mdf convert-md`: converts Markdown into a paged MDF document.
- `mdf render`: exports page PNGs and generates an `index.html` with page navigation.
- `mdf info`, `mdf list-chunks`, `mdf unpack`, `mdf extract`: inspection and extraction tools for automation and debugging.

## Spec

See `docs/FORMAT.md`.

## Build the Zig CLI

```bash
cd zig
zig build
./zig-out/bin/mdf --help
```

## Native GUI reader (no web stack)

There is a native GUI reader at `apps/mdf-reader` built with **Zig + SDL2**.

```bash
cd apps/mdf-reader
zig build
./zig-out/bin/mdf-reader ../../examples/output/sample.mdf
```

## CLI usage

### Wrap bytes + verify

```bash
# Convert any input into an MDF container (deterministic by default)
node ./bin/mdf.js convert ./test/fixtures/plain.txt --output ./examples/output/plain.mdf
node ./bin/mdf.js verify ./examples/output/plain.mdf

# Zig CLI output is byte-for-byte compatible with the JS CLI:
./zig/zig-out/bin/mdf convert ./test/fixtures/plain.txt --output ./examples/output/plain.zig.mdf
./zig/zig-out/bin/mdf verify ./examples/output/plain.zig.mdf
```

### Demo and Markdown conversion (no extra tools)

```bash
./zig/zig-out/bin/mdf demo --output ./examples/output/demo.mdf
./zig/zig-out/bin/mdf render ./examples/output/demo.mdf --output-dir ./examples/output/demo.render

./zig/zig-out/bin/mdf convert-md ./examples/input/sample.md --output ./examples/output/sample.mdf
./zig/zig-out/bin/mdf render ./examples/output/sample.mdf --output-dir ./examples/output/sample.render
```

### Optional render-based converters (require external tools)

- PDF rendering: `mutool` (MuPDF)
- Typst: `typst` + `mutool`
- LaTeX: `latexmk` + `mutool`

```bash
./zig/zig-out/bin/mdf convert-pdf ./test/fixtures/minimal.pdf --output ./examples/output/minimal.mdf
./zig/zig-out/bin/mdf render ./examples/output/minimal.mdf --output-dir ./examples/output/minimal.render
open ./examples/output/minimal.render/index.html
```

### Inspect and extract

```bash
./zig/zig-out/bin/mdf info ./examples/output/sample.mdf
./zig/zig-out/bin/mdf list-chunks ./examples/output/sample.mdf
./zig/zig-out/bin/mdf unpack ./examples/output/sample.mdf --output-dir ./examples/output/sample.unpacked
./zig/zig-out/bin/mdf extract ./examples/output/sample.mdf --type DOCM --output ./examples/output/docm.json
```

## Tests

```bash
npm test
```

## What’s not implemented (yet)

- Platform-native reader apps (Windows/macOS/Linux/iOS/Android)
- Designer/editor “studio” application
- A true vector/text layout model (current paged mode packages raster page images)

## License

MIT. See `LICENSE`.
