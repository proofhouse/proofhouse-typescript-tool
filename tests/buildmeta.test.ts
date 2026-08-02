// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { readFileSync } from "node:fs";
import { afterEach, describe, expect, it, vi } from "vitest";

import { get } from "../src/buildmeta.ts";
import { COMMIT, DATE } from "../src/generated/buildinfo.ts";

// A checkout always carries a well-formed manifest, so the guard in the source
// never sees anything worth rejecting here. Standing in front of the reader is
// what lets a case hand it something else. The module below arrives through a
// mock that forwards to the real reader until a case says otherwise.
vi.mock("node:fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:fs")>();
  return { ...actual, readFileSync: vi.fn(actual.readFileSync) };
});

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

// Four texts, four clauses of the guard. A bare number never reaches the shape
// checks. `null` slips past `typeof` and stops at the equality test beside it.
// The empty object has no version key. The last one has a version of the wrong
// type.
const REJECTED_MANIFESTS = ["7", "null", "{}", '{"version": 7}'];

describe("get on an unusable manifest", () => {
  afterEach(() => {
    vi.mocked(readFileSync).mockReset();
  });

  it.each(REJECTED_MANIFESTS)("refuses to report a version from %s", (text) => {
    vi.mocked(readFileSync).mockReturnValueOnce(text);
    expect(() => get()).toThrow(TypeError);
  });
});

describe("the generated stamp module", () => {
  it("exports a string for both values", () => {
    expect(typeof COMMIT).toBe("string");
    expect(typeof DATE).toBe("string");
  });
});
