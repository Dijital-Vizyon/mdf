import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { buildMdfDocument, parseMdfDocument } from "../src/mdf-format.js";

const repoRoot = process.cwd();
const cliPath = path.join(repoRoot, "bin", "mdf.js");

test("buildMdfDocument creates a readable MDF container", () => {
  const buffer = buildMdfDocument({
    sourcePath: "plain.txt",
    sourceBytes: Buffer.from("hello world", "utf8"),
    optimizeRaster: true,
    quality: 80
  });

  const parsed = parseMdfDocument(buffer);

  assert.equal(parsed.version, "0.1");
  assert.equal(parsed.chunkCount, 2);
  assert.deepEqual(parsed.chunks.map((chunk) => chunk.type), ["META", "DATA"]);
});

test("buildMdfDocument is deterministic by default (stable META)", () => {
  const sourceBytes = Buffer.from("hello world", "utf8");
  const a = buildMdfDocument({
    sourcePath: "plain.txt",
    sourceBytes,
    optimizeRaster: false,
    quality: null
  });
  const b = buildMdfDocument({
    sourcePath: "plain.txt",
    sourceBytes,
    optimizeRaster: false,
    quality: null
  });

  assert.ok(a.equals(b), "Expected identical bytes for identical input without stampTime.");
});

test("CLI convert and verify succeed end to end", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "mdf-cli-"));
  const input = path.join(tempDir, "input.txt");
  const output = path.join(tempDir, "output.mdf");

  await fs.writeFile(input, "integration test");

  const convert = spawnSync(process.execPath, [cliPath, "convert", input, "--output", output, "--quality", "75"], {
    cwd: repoRoot,
    encoding: "utf8"
  });

  assert.equal(convert.status, 0, convert.stderr);
  assert.match(convert.stdout, /Wrote/);

  const verify = spawnSync(process.execPath, [cliPath, "verify", output], {
    cwd: repoRoot,
    encoding: "utf8"
  });

  assert.equal(verify.status, 0, verify.stderr);
  assert.match(verify.stdout, /Zero executable chunks detected/);
});

test("CLI verify rejects invalid MDF input", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "mdf-cli-invalid-"));
  const input = path.join(tempDir, "broken.mdf");

  await fs.writeFile(input, "not-an-mdf-file");

  const verify = spawnSync(process.execPath, [cliPath, "verify", input], {
    cwd: repoRoot,
    encoding: "utf8"
  });

  assert.equal(verify.status, 1);
  assert.match(verify.stderr, /(Input is too small to be a valid MDF document|Invalid MDF signature)/);
});
