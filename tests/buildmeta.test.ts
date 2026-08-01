// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { get } from "../src/buildmeta.ts";
import { COMMIT, DATE } from "../src/generated/buildinfo.ts";

// Read the manifest here too, rather than through the code under test, so the
// expectation has its own path to the value.
function manifestVersion(): string {
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

// Every assertion holds whether or not the checkout has been stamped, so the
// suite reports the same result from a bare clone and from a built tree.
describe("get", () => {
  it("reports the version the package manifest declares", () => {
    expect(get().version).toBe(manifestVersion());
  });

  it("reports either no commit or a seven-character short SHA", () => {
    expect(get().commit).toMatch(/^(?:|[0-9a-f]{7})$/);
  });

  it("reports either an unknown date or one opening with a year", () => {
    expect(get().date).toMatch(/^(?:unknown$|\d{4})/);
  });
});

describe("the generated stamp module", () => {
  it("exports a string for both values", () => {
    expect(typeof COMMIT).toBe("string");
    expect(typeof DATE).toBe("string");
  });
});
