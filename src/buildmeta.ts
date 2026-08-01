// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { readFileSync } from "node:fs";

import { COMMIT, DATE } from "./generated/buildinfo.ts";

// A static import of package.json would pull it under the build's `rootDir` and
// reshape dist around it. Reading the manifest at runtime avoids that. The
// relative URL resolves the same from src/ in a checkout as from the emitted JS
// in a packed tarball, one level up in each.
function readVersion(): string {
  const text = readFileSync(new URL("../package.json", import.meta.url), "utf8");
  const manifest: unknown = JSON.parse(text);
  if (
    typeof manifest !== "object" ||
    manifest === null ||
    !("version" in manifest) ||
    typeof manifest.version !== "string"
  ) {
    throw new TypeError("package.json carries no version string");
  }
  return manifest.version;
}

/** Build-time facts the tool reports about itself. */
export interface BuildInfo {
  /** Package version, read from the manifest that travels with the code. */
  readonly version: string;
  /** Short git SHA the build came from, empty when nothing stamped it. */
  readonly commit: string;
  /** Calendar date of the build, "unknown" when nothing stamped it. */
  readonly date: string;
}

/** Return the build metadata of the running tool. */
export function get(): BuildInfo {
  return { version: readVersion(), commit: COMMIT, date: DATE };
}
