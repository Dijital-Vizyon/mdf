# MDF Markdown Stress Test

This document is intentionally dense. It’s used to validate conversion, rendering, and parsing behavior under realistic content and edge-cases.

## 1) Typography and inline formatting

Normal text, **bold text**, *italic text*, and mixed **bold with *italic inside***.

Inline punctuation and symbols:
- commas, periods, colons:, semicolons; dashes - and em-dash style --- sequences
- parentheses (like this), brackets [like this], braces {like this}
- quotes: "double quotes" and 'single quotes'
- slashes / backslashes \\ and underscores_like_this and `inline code`

A very long line (to test wrapping and clipping): Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

## 2) Headings hierarchy

# H1 Title (already above)
## H2 Section
### H3 Subsection
#### H4 Small heading
##### H5 Smaller heading
###### H6 Smallest heading

## 3) Lists (nested, ordered, mixed)

- Bullet level 1
  - Bullet level 2
    - Bullet level 3
  - Another level 2 item with **bold** and *italic*
- Another level 1 item

1. Ordered item one
2. Ordered item two
   1. Nested ordered A
   2. Nested ordered B
3. Ordered item three

- Mixed list starts
  1. Ordered inside bullet
  2. Another ordered inside bullet
  - Bullet inside ordered-inside-bullet (yes, messy on purpose)

## 4) Blockquotes

> Quote level 1: “Documents should be data, not programs.”
>
> > Quote level 2: nested quote
> >
> > - quoted list item A
> > - quoted list item B

## 5) Code blocks

Inline code: `mdf verify file.mdf`

Fenced code (JS):

```js
export function add(a, b) {
  return a + b;
}
```

Fenced code (Zig):

```zig
const std = @import("std");
pub fn main() void {
    std.debug.print("hello\\n", .{});
}
```

Fenced code (shell):

```bash
cd zig
zig build
./zig-out/bin/mdf demo --output ../examples/output/demo.mdf
```

## 6) Tables

| Feature | Expected | Notes |
|---|---:|---|
| Deterministic output | yes | same input → same bytes |
| Chunk validation | yes | CRC32 per chunk |
| Streaming parse | yes | linear chunk layout |
| Execution disabled | yes | reject known executable chunk types |

Alignment test:

| left | center | right |
|:---|:---:|---:|
| a | b | c |
| 1 | 2 | 3 |

## 7) Links and references

- Project root: `./`
- Relative link example: [Spec](../docs/FORMAT.md)
- A URL-looking string (not necessarily clickable): https://example.com/path?query=1

## 8) Images (as Markdown syntax)

These are placeholders for future tooling; they may not resolve during conversion yet:

![Alt text: logo](./image-does-not-exist.png)
![Alt text: diagram](../docs/diagram.png)

## 9) Checklists / tasks

- [ ] item not done
- [x] item done
- [ ] another item not done

## 10) Edge cases

Empty lines follow.



Non-ASCII (UTF-8) text:
- café, naïve, résumé
- Ελληνικά, 日本語, العربية

Emoji-like characters (still text): ✓ ✗ ★ → ←

## 11) Paragraph density

Paragraph 1. This paragraph is short.

Paragraph 2. This paragraph is longer and contains multiple sentences. It should help verify baseline paragraph layout, line breaks, and spacing decisions for a real renderer and real font shaping integration later.

Paragraph 3. End.

