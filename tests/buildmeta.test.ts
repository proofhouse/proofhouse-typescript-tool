// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { get } from "../src/buildmeta.ts";
import { COMMIT, DATE } from "../src/generated/buildinfo.ts";

// Read the manifest here too, rather than through the code under test, so the
// expectation has its own path to the value. The narrowing the source performs
// on the parsed object is deliberately not repeated: a helper that walked the
// same checks would be a copy of the function it exists to check, and the
// assertion below fails on a missing version either way.
function manifestVersion(): string {
  const text = readFileSync(new URL("../package.json", import.meta.url), "utf8");
  return (JSON.parse(text) as { version: string }).version;
}

const EMPTY_OR_SHORT_SHA = /^(?:|[0-9a-f]{7})$/;
const UNKNOWN_OR_YEAR = /^(?:unknown$|\d{4})/;

// Every assertion holds on a stamped checkout and an unstamped one alike, so
// the suite reports the same result from a bare clone and from a built tree.
describe("get", () => {
  it("reports the version the package manifest declares", () => {
    expect(get().version).toBe(manifestVersion());
  });

  it("reports either no commit or a seven-character short SHA", () => {
    expect(get().commit).toMatch(EMPTY_OR_SHORT_SHA);
  });

  it("reports either an unknown date or one opening with a year", () => {
    expect(get().date).toMatch(UNKNOWN_OR_YEAR);
  });
});

describe("the generated stamp module", () => {
  it("exports a string for both values", () => {
    expect(typeof COMMIT).toBe("string");
    expect(typeof DATE).toBe("string");
  });
});
