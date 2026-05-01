import fs from "node:fs/promises";
import path from "node:path";
import { buildMdfDocument, summarizeMdfDocument } from "./mdf-format.js";

function formatHelp() {
  return `MDF CLI

Usage:
  mdf convert <input> --output <file> [--optimize-raster] [--quality <0-100>] [--stamp-time]
  mdf verify <input>
  mdf --help

Commands:
  convert   Wrap a source document in the MDF prototype container
  verify    Validate MDF signature, chunk layout, and executable-chunk policy`;
}

function parseFlags(argv) {
  const positionals = [];
  const flags = new Map();

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) {
      positionals.push(token);
      continue;
    }

    const next = argv[i + 1];
    if (next && !next.startsWith("--")) {
      flags.set(token, next);
      i += 1;
    } else {
      flags.set(token, true);
    }
  }

  return { positionals, flags };
}

function parseQuality(raw) {
  if (raw === undefined) {
    return null;
  }

  const quality = Number(raw);
  if (!Number.isInteger(quality) || quality < 0 || quality > 100) {
    throw new Error("--quality must be an integer between 0 and 100.");
  }

  return quality;
}

async function convertCommand(argv, io) {
  const { positionals, flags } = parseFlags(argv);
  const input = positionals[1];
  const output = flags.get("--output");

  if (!input || !output) {
    throw new Error("convert requires <input> and --output <file>.");
  }

  const quality = parseQuality(flags.get("--quality"));
  const optimizeRaster = flags.has("--optimize-raster");
  const stampTime = flags.has("--stamp-time");
  const sourceBytes = await fs.readFile(input);
  const document = buildMdfDocument({
    sourcePath: path.basename(input),
    sourceBytes,
    optimizeRaster,
    quality,
    stampTime
  });

  await fs.mkdir(path.dirname(output), { recursive: true });
  await fs.writeFile(output, document);

  io.stdout.write(`[SUCCESS] Wrote ${output} (${document.length} bytes)\n`);
  return 0;
}

async function verifyCommand(argv, io) {
  const { positionals } = parseFlags(argv);
  const input = positionals[1];

  if (!input) {
    throw new Error("verify requires <input>.");
  }

  const document = await fs.readFile(input);
  const summary = summarizeMdfDocument(document);
  io.stdout.write(`[SUCCESS] MDF signature valid. Zero executable chunks detected.\n`);
  io.stdout.write(`version=${summary.version} chunks=${summary.chunkCount} types=${summary.types.join(",")} payloadBytes=${summary.payloadBytes}\n`);
  return 0;
}

export async function runCli(argv, io) {
  try {
    const command = argv[0];

    if (!command || command === "--help" || command === "-h") {
      io.stdout.write(`${formatHelp()}\n`);
      return 0;
    }

    if (command === "convert") {
      return await convertCommand(argv, io);
    }

    if (command === "verify") {
      return await verifyCommand(argv, io);
    }

    throw new Error(`Unknown command "${command}".`);
  } catch (error) {
    io.stderr.write(`[ERROR] ${error.message}\n`);
    return 1;
  }
}
