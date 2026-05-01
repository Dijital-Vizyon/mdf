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

test("Zig CLI info/list/unpack/extract work on a demo MDF", async () => {
  buildZigOnce();

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "mdf-tools-"));
  const mdfPath = path.join(tempDir, "demo.mdf");
  const outDir = path.join(tempDir, "unpacked");
  const extracted = path.join(tempDir, "docm.json");

  const demo = spawnSync(zigBin, ["demo", "--output", mdfPath], { cwd: repoRoot, encoding: "utf8" });
  assert.equal(demo.status, 0, demo.stderr);

  const info = spawnSync(zigBin, ["info", mdfPath], { cwd: repoRoot, encoding: "utf8" });
  assert.equal(info.status, 0, info.stderr);
  assert.match(info.stdout, /version=\d+\.\d+ chunks=\d+/);

  const list = spawnSync(zigBin, ["list-chunks", mdfPath], { cwd: repoRoot, encoding: "utf8" });
  assert.equal(list.status, 0, list.stderr);
  assert.match(list.stdout, /^idx type flags length crc32/m);

  const unpack = spawnSync(zigBin, ["unpack", mdfPath, "--output-dir", outDir], { cwd: repoRoot, encoding: "utf8" });
  assert.equal(unpack.status, 0, unpack.stderr);
  const manifest = await fs.readFile(path.join(outDir, "manifest.json"), "utf8");
  assert.match(manifest, /"chunks":\[/);

  const extract = spawnSync(zigBin, ["extract", mdfPath, "--type", "DOCM", "--output", extracted], {
    cwd: repoRoot,
    encoding: "utf8"
  });
  assert.equal(extract.status, 0, extract.stderr);
  const docm = await fs.readFile(extracted, "utf8");
  assert.match(docm, /"pages"/);
});

