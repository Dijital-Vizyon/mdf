# MDF Format Specification

This document describes the MDF binary container format implemented by this repository.

## Design goals

- **Deterministic**: same inputs and options produce the same bytes (unless explicitly opting into non-determinism).
- **Streamable**: linear layout; readers can parse chunks in a single pass.
- **Secure-by-policy**: the reference verifier rejects known executable chunk types.

## File structure (high level)

An MDF file is:

1. A fixed-size header (16 bytes)
2. A sequence of chunks (count given in the header)
3. No trailing bytes after the last chunk

## Header (16 bytes)

All integer fields are **little-endian** unless otherwise noted.

Offset | Size | Field | Meaning
---:|---:|---|---
0 | 4 | `magic` | ASCII `MDF1`
4 | 1 | `version_major` | e.g. `0`
5 | 1 | `version_minor` | e.g. `1` or `2`
6 | 2 | `reserved0` | must be `0` (writers set to zero; readers may ignore)
8 | 4 | `chunk_count` | number of chunks following the header
12 | 4 | `reserved1` | must be `0` (writers set to zero; readers may ignore)

## Chunk layout (16-byte header + payload)

Each chunk is:

Field | Size | Type | Meaning
---|---:|---|---
`type` | 4 | ASCII | chunk type code (recommended: `A–Z`, `0–9`, `_`)
`flags` | 4 | u32 | reserved for future use; writers in this repo set `0`
`length` | 4 | u32 | payload length in bytes
`crc32` | 4 | u32 | CRC32 of the payload only (IEEE / Ethernet polynomial)
`payload` | `length` | bytes | chunk data

### CRC32

CRC32 is computed over the payload bytes only, using the standard IEEE polynomial (same as common `crc32` implementations).

### Parsing rules

Readers/verifiers must reject:
- file smaller than 16 bytes
- bad magic
- any chunk header that would exceed file length
- any chunk payload that would exceed file length
- CRC mismatch for any chunk
- any trailing bytes after parsing exactly `chunk_count` chunks

## Security policy (reference verifier)

The reference verifier rejects any MDF file containing a chunk whose `type` is one of:

- `EXEC`, `JS__`, `CODE`, `XCMD`

This is a policy layer on top of structural validation and CRC checks.

## Chunk types used by this repository

### Container mode (`0.1`)

This repo’s container conversion (`convert`) writes:

- `META`: UTF-8 JSON metadata (deterministic by default)
- `DATA`: raw input bytes

### Paged document mode (`0.2`)

This repo’s “paged” document packaging (used by `demo`, `convert-md`, and optional render-based converters) writes:

- `DOCM`: UTF-8 JSON manifest
- `PAGE`: UTF-8 JSON page entries
- `IMG_`: binary payload `[imageId(u32le)] + pngBytes`

#### `DOCM` JSON

The manifest contains a pages array. Minimal shape:

```json
{
  "version": 2,
  "pages": [
    { "index": 0, "width": 1200, "height": 1600, "imageId": 1 }
  ]
}
```

#### `PAGE` JSON

Each page entry is also written as its own `PAGE` chunk using the same keys:

```json
{ "index": 0, "width": 1200, "height": 1600, "imageId": 1 }
```

#### `IMG_` payload

`IMG_` payload layout:

- bytes `0..4`: `imageId` (u32le)
- bytes `4..end`: raw PNG bytes

## Versioning

- The header’s `version_major`/`version_minor` describe the overall file interpretation.
- This repo currently writes `0.1` for container conversion and `0.2` for paged packaging.

