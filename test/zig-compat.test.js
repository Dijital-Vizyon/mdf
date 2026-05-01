import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const repoRoot = process.cwd();
const zigDir = path.join(repoRoot, "zig");
const zigBin = path.join(zigDir, "zig-out", "bin", "mdf");
const jsCli = path.join(repoRoot, "bin", "mdf.js");

function buildZigOnce() {
  const build = spawnSync("zig", ["build"], { cwd: zigDir, encoding: "utf8" });
  assert.equal(build.status, 0, build.stderr || build.stdout);
}

test("Zig CLI convert matches JS CLI bytes (deterministic META)", async () => {
  buildZigOnce();

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "mdf-zig-compat-"));
  const input = path.join(tempDir, "input.txt");
  const outJs = path.join(tempDir, "js.mdf");
  const outZig = path.join(tempDir, "zig.mdf");

  await fs.writeFile(input, "compat test");

  const runJs = spawnSync(process.execPath, [jsCli, "convert", input, "--output", outJs], {
    cwd: repoRoot,
    encoding: "utf8"
  });
  assert.equal(runJs.status, 0, runJs.stderr);

  const runZig = spawnSync(zigBin, ["convert", input, "--output", outZig], {
    cwd: repoRoot,
    encoding: "utf8"
  });
  assert.equal(runZig.status, 0, runZig.stderr);

  const [a, b] = await Promise.all([fs.readFile(outJs), fs.readFile(outZig)]);
  assert.ok(a.equals(b), "Expected Zig output to be byte-for-byte identical to JS output.");
});

