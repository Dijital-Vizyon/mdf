# Examples

Prototype usage from the repository root:

```bash
node ./bin/mdf.js convert ./examples/input/hello.txt --output ./examples/output/hello.mdf
node ./bin/mdf.js verify ./examples/output/hello.mdf
```

The converter currently wraps an input document inside the MDF prototype container and emits metadata plus a binary data chunk.

## Markdown → MDF (Zig)

This repo also includes a Markdown converter in the Zig CLI that renders Markdown into a page image and packages it as MDF, so you can immediately export it with `render`.

```bash
cd zig
zig build
cd ..

./zig/zig-out/bin/mdf convert-md ./examples/input/sample.md --output ./examples/output/sample.mdf
./zig/zig-out/bin/mdf render ./examples/output/sample.mdf --output-dir ./examples/output/sample.render
open ./examples/output/sample.render/index.html
```

## Inspect and extract (Zig)

```bash
./zig/zig-out/bin/mdf info ./examples/output/sample.mdf
./zig/zig-out/bin/mdf list-chunks ./examples/output/sample.mdf
./zig/zig-out/bin/mdf unpack ./examples/output/sample.mdf --output-dir ./examples/output/sample.unpacked
./zig/zig-out/bin/mdf extract ./examples/output/sample.mdf --type DOCM --output ./examples/output/docm.json
```
