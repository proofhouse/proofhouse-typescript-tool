// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import fc, { type Arbitrary } from "fast-check";

import type { BuildInfo } from "../../src/buildmeta.ts";

// A line break inside a build fact would move the version block off the three
// lines every tool in the organization prints. No stamp can produce one.
// Everything else in the Unicode range stays fair game here. Control
// characters sit in that range too. The filter below is what turns them away.
const LINE_BREAK = /[\n\r]/;

function text(): Arbitrary<string> {
  return fc.string({ unit: "binary" }).filter((value) => !LINE_BREAK.test(value));
}

/**
 * Draw the build facts a checkout can report about itself.
 *
 * The unstamped spellings are drawn often rather than left to chance, since
 * an empty commit and an unknown date are what a plain clone reports and a
 * law that skipped them would miss the common case.
 *
 * @returns Version, commit, and date triples covering stamped and bare trees.
 */
export function stamps(): Arbitrary<BuildInfo> {
  return fc.record({
    version: text(),
    commit: fc.oneof(fc.constant(""), text()),
    date: fc.oneof(fc.constant("unknown"), text()),
  });
}
