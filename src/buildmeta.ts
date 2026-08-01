// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { readFileSync } from "node:fs";

import { COMMIT, DATE } from "./generated/buildinfo.ts";

/** Build-time facts the tool reports about itself. */
export interface BuildInfo {
  /** Package version, taken from the manifest shipped alongside the code. */
  readonly version: string;
  /** Short git SHA the build came from, empty when nothing stamped it. */
  readonly commit: string;
  /** Calendar date of the build, "unknown" when nothing stamped it. */
  readonly date: string;
}

// The manifest is read at runtime instead of imported as JSON. A static import
// would pull package.json under the build's rootDir and reshape dist around it.
// The relative URL finds the manifest either way: one level above src/ in a
// checkout, and one level above the emitted JS in a packed tarball.
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

/** Return the build metadata of the running tool. */
export function get(): BuildInfo {
  return { version: readVersion(), commit: COMMIT, date: DATE };
}
