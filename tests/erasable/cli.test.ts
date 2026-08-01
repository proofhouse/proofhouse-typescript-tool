// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import process from "node:process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

// This suite runs on Node's own test runner rather than under `vitest`, and
// that's the whole point of it. Nothing transforms the sources on the way in,
// so the run reaches its first assertion only if Node stripped the types off
// the entry point and everything it imports. A transform ahead of the file
// would answer for syntax the runtime can't erase, and the failure would
// never surface.

const NAME_LINE = /^proofhouse-typescript-tool /;
const COMMIT_LINE = /^commit: /;
const DATE_LINE = /^date: {3}/;

// The version output ends in a newline, so splitting it leaves a fourth,
// empty part.
const VERSION_OUTPUT_PARTS = 4;

const root = fileURLToPath(new URL("../..", import.meta.url));

// `test` hands back a promise that settles once the case is done, and the
// runner reports the result even when nobody reads that promise. Awaiting it
// here keeps the module from finishing ahead of the case it registered.
await test("the entry point runs as TypeScript under Node", () => {
  const result = spawnSync(process.execPath, ["src/cli.ts", "version"], {
    cwd: root,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);

  const lines = result.stdout.split("\n");
  assert.equal(lines.length, VERSION_OUTPUT_PARTS);
  assert.match(lines[0] ?? "", NAME_LINE);
  assert.match(lines[1] ?? "", COMMIT_LINE);
  assert.match(lines[2] ?? "", DATE_LINE);
  assert.equal(lines[3], "");
});
