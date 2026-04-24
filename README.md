# MDF: Modern Document Format

![Version](https://img.shields.io/badge/version-0.1.0--alpha-orange.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Security](https://img.shields.io/badge/security-Zero--JS-success.svg)
![Platform](https://img.shields.io/badge/platform-Cross--Platform-lightgrey.svg)

**MDF (Modern Document Format)** is a deterministic, high-performance, and strictly secure document standard engineered to replace legacy formats. 

By fundamentally redesigning document architecture from the ground up, MDF eliminates execution environments (such as JavaScript), strips away decades of specification bloat, and provides a streamlined binary structure optimized for sub-millisecond parsing and pixel-perfect rendering across all operating systems.

---

## 🛑 The Problem with Legacy Formats

Standards like PDF were designed in the 1990s and have accumulated massive technical debt. Today, they suffer from:
1. **Critical Security Flaws:** Support for embedded JavaScript, macros, and interactive forms turns documents into active execution environments, leading to countless CVEs.
2. **Specification Bloat:** The PDF 2.0 specification is nearly 1,000 pages long, making it nearly impossible to write a parser from scratch without inconsistencies.
3. **Rendering Inconsistencies:** Because the spec is so complex, a document often looks different in Adobe Acrobat, Chrome, macOS Preview, and mobile readers.
4. **Heavy Resource Usage:** Parsing legacy formats requires massive memory overhead and complex rendering engines.

---

## ⚡ The MDF Solution & Architecture

MDF solves these issues through strict architectural constraints and modern binary design.

### 1. Zero-Execution Environment (Secure by Design)
MDF is a purely declarative format. It contains **zero** support for JavaScript, macros, or external executable calls. An MDF file cannot compute; it can only be displayed. This guarantees that opening an MDF file will never compromise a system.

### 2. Linear Binary Streaming
Unlike legacy formats that scatter xref tables and objects randomly throughout the file (requiring the entire file to be loaded or complex byte-jumping to parse), MDF utilizes a strictly linear, chunk-based binary structure. This allows readers to stream the document, rendering page 1 instantly while the rest of the file buffers.

### 3. Immutable Layout Engine
MDF requires absolute positioning and explicitly defined vector paths. It does not rely on the host OS for text shaping or font rendering. All necessary font subsets and glyph data are embedded securely, guaranteeing 100% pixel-perfect output regardless of the viewer.

---

## 📊 Comparison: MDF vs. PDF

| Feature | PDF (Portable Document Format) | MDF (Modern Document Format) |
| :--- | :--- | :--- |
| **Execution Layer** | Embedded JavaScript, Macros | **None (Strictly Static)** |
| **Security Risk** | High (Frequent CVEs & Exploits) | **Negligible (Data-only payload)** |
| **Parsing Speed** | Slow (Complex object graphs) | **Extremely Fast (Linear binary)** |
| **Rendering Consistency**| Varies wildly across readers | **Pixel-perfect guarantee** |
| **File Structure** | Text/Binary hybrid, scattered tables | **Optimized Binary Chunks** |
| **Primary Use Case** | Legacy enterprise, interactive forms | **Secure, fast, universal reading** |

---

## 🧩 The Ecosystem Toolkit

MDF is not just a file extension; it is supported by a comprehensive suite of open-source tools:

### `mdf-core` (The Specification)
The core library and binary specification governing how data is encoded. Written in memory-safe languages to prevent buffer overflows during parsing.

### `mdf-cli` & GUI Converters
Robust conversion tools to migrate existing documents into the MDF standard.
* **CLI:** Headless tool for batch processing, server-side conversion, and CI/CD pipelines.
* **GUI:** A desktop application for one-click document conversion.

### Native MDF Readers
Lightning-fast viewing applications built natively for:
* **Windows** (C++/DirectX)
* **macOS/iOS** (Swift/Metal)
* **Linux** (Rust/Wayland)
* **Android** (Kotlin/Canvas)

### MDF Designer
A standalone visual editor allowing creators to design, manipulate, and author native MDF documents without needing to convert from other formats.

---

## 💻 Getting Started

### Installation
*Note: Binaries are currently in the pre-release phase.*

```bash
# Install the CLI converter globally
npm install -g mdf-cli

# Or via Homebrew (macOS)
brew install mdf-tools
```

### CLI Usage

**Convert a PDF to MDF:**
```bash
mdf convert input.pdf --output document.mdf
```

**Convert and aggressively compress image streams:**
```bash
mdf convert input.pdf --output compressed.mdf --optimize-raster --quality 80
```

**Verify an MDF file's structural integrity:**
```bash
mdf verify document.mdf
# Output: [SUCCESS] MDF signature valid. Zero executable chunks detected.
```

---

## 🤝 Contributing

We are building the future of digital documents. Whether you are a Rust developer looking to optimize the core parser, a Swift developer building the macOS reader, or a technical writer improving the spec, your contributions are critical.

Please review our `CONTRIBUTING.md` for coding standards, pull request processes, and architectural guidelines. 

## 📄 License

MDF and its core tooling are released under the **MIT License**. We believe fundamental document standards must remain free and open forever.
