// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import process from "node:process";
import fc from "fast-check";

// What an inner loop run on each save can afford.
const DRAWS_PER_PROPERTY = 100;

// Every property draws that many cases unless the surroundings say otherwise,
// and the variable is where a wider search comes from: a long run becomes a
// decision made when the run starts rather than an edit to a suite. The count
// reaches every property at once, since fast-check reads these settings as a
// run begins and no suite here passes its own.

// biome-ignore lint/style/noProcessEnv: a budget the caller sets has nowhere else to arrive from, and this is the one line that reads it.
// biome-ignore lint/complexity/useLiteralKeys: `noPropertyAccessFromIndexSignature` in the compiler options wants the index form on an index signature.
fc.configureGlobal({ numRuns: Number(process.env["FC_NUM_RUNS"] ?? DRAWS_PER_PROPERTY) });
