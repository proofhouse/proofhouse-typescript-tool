// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { readFileSync } from "node:fs";
import { test } from "@fast-check/vitest";
import fc, { type Arbitrary } from "fast-check";
import { afterEach, describe, expect, vi } from "vitest";

import { type BuildInfo, get } from "../../src/buildmeta.ts";
import { stamps } from "./stamps.ts";

// The generated module is a pair of constants that a build rewrites, so a
// draw reaches the reader only through a stand-in. The factory hands back the
// holder itself rather than a copy of what it says: the factory runs once
// while the draws keep coming, and each read has to arrive at the value the
// current draw put there.
// biome-ignore lint/style/useNamingConvention: the stand-in has to answer to the names the generated module exports.
const stamp = vi.hoisted(() => ({ COMMIT: "", DATE: "unknown" }));

vi.mock("../../src/generated/buildinfo.ts", () => stamp);

// A spy over the real module rather than a replacement of it. The manifest
// still comes off disk until a case hands the reader something else.
vi.mock("node:fs", { spy: true });

// The version is read off the manifest and not off the stamp, so it holds
// still while the drawn values move. One read here gives the first law
// something to hold the answer against.
const VERSION = get().version;

// A refusal here always arrives typed. JSON.parse rejects a text that never
// was a document. The guard inside the reader rejects a document with no
// usable version in it. Anything else escaping the call is the defect the
// second law below exists to catch.
const REFUSALS = [SyntaxError, TypeError];

// The sources of manifest text widen as they go. Raw bytes rarely parse at
// all. A JSON document of any shape reaches the guard itself. The last source
// builds its document around a version the reader can use.
function manifests(): Arbitrary<string> {
  return fc.oneof(
    fc.string({ unit: "binary" }),
    fc.jsonValue().map((value) => JSON.stringify(value)),
    stamps().map((info) => JSON.stringify(info)),
  );
}

describe("get", () => {
  test.prop([stamps()])("hands back whatever stamp it found", ({ commit, date }) => {
    stamp.COMMIT = commit;
    stamp.DATE = date;

    expect(get()).toEqual({ version: VERSION, commit, date });
  });
});

describe("get on an arbitrary manifest", () => {
  afterEach(() => {
    vi.mocked(readFileSync).mockReset();
  });

  test.prop([manifests()])("answers any text with a version or a refusal", (manifest) => {
    vi.mocked(readFileSync).mockReturnValue(manifest);

    let info: BuildInfo;
    try {
      info = get();
    } catch (error) {
      expect(REFUSALS.some((kind) => error instanceof kind)).toBe(true);
      return;
    }

    expect(typeof info.version).toBe("string");
  });
});
