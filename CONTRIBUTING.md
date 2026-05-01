# Contributing

This repository contains the reference MDF prototype and its CLI tooling.

## Development

```bash
npm test
node ./bin/mdf.js --help
```

## Project Layout

- `bin/`: executable entrypoints
- `src/`: MDF format and CLI implementation
- `examples/`: sample inputs and usage notes
- `test/`: integration and format tests

## Contribution Guidelines

1. Keep the MDF container deterministic. Changes that alter the binary layout must include tests.
2. Avoid adding runtime dependencies unless they materially improve the prototype.
3. Preserve the zero-execution design of the MDF format itself. The file format is data only.
4. Add or update tests for new commands, flags, and validation rules.

## Pull Requests

Open focused pull requests with a short summary of the user-visible change and the tests you ran.
