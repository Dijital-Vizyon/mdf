import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const repoRoot = process.cwd();
const zigDir = path.join(repoRoot, "zig");
const zigBin = path.join(zigDir, "zig-out", "bin", "mdf");

function buildZigOnce() {
  const build = spawnSync("zig", ["build"], { cwd: zigDir, encoding: "utf8" });
  assert.equal(build.status, 0, build.stderr || build.stdout);
}

test("Zig CLI demo generates MDF and render exports index.html", async () => {
  buildZigOnce();

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "mdf-demo-"));
  const out = path.join(tempDir, "demo.mdf");
  const renderDir = path.join(tempDir, "render");

  const demo = spawnSync(zigBin, ["demo", "--output", out], { cwd: repoRoot, encoding: "utf8" });
  assert.equal(demo.status, 0, demo.stderr);

  const st = await fs.stat(out);
  assert.ok(st.size > 10_000, "Expected demo MDF to be non-trivially sized.");

  const render = spawnSync(zigBin, ["render", out, "--output-dir", renderDir], { cwd: repoRoot, encoding: "utf8" });
  assert.equal(render.status, 0, render.stderr);

  const indexHtml = await fs.readFile(path.join(renderDir, "index.html"), "utf8");
  assert.match(indexHtml, /const pages =/);

  // At least one page image should exist.
  const files = await fs.readdir(renderDir);
  assert.ok(files.some((f) => f.endsWith(".png")), "Expected at least one rendered PNG.");
});

test("Zig CLI convert-md converts Markdown and render exports index.html", async () => {
  buildZigOnce();

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "mdf-md-"));
  const input = path.join(repoRoot, "examples", "input", "sample.md");
  const out = path.join(tempDir, "sample.mdf");
  const renderDir = path.join(tempDir, "render");

  const conv = spawnSync(zigBin, ["convert-md", input, "--output", out], { cwd: repoRoot, encoding: "utf8" });
  assert.equal(conv.status, 0, conv.stderr);

  const render = spawnSync(zigBin, ["render", out, "--output-dir", renderDir], { cwd: repoRoot, encoding: "utf8" });
  assert.equal(render.status, 0, render.stderr);

  const indexHtml = await fs.readFile(path.join(renderDir, "index.html"), "utf8");
  assert.match(indexHtml, /const pages =/);
});

