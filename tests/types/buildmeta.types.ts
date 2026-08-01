// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { expectTypeOf } from "expect-type";

import { type BuildInfo, get } from "../../src/buildmeta.ts";

// Assertions here are checked by the compiler, which the typecheck gate runs
// over this directory along with the rest of the tree. vitest collects only
// files ending in .test.ts, so nothing here reaches the runner. The assertion
// methods do exist at run time and do nothing when called.

expectTypeOf(get).returns.toEqualTypeOf<BuildInfo>();

expectTypeOf<BuildInfo>().toEqualTypeOf<{
  readonly version: string;
  readonly commit: string;
  readonly date: string;
}>();

expectTypeOf<BuildInfo>().toHaveProperty("version").toEqualTypeOf<string>();
