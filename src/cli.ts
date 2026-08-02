#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

/* v8 ignore file -- @preserve: reaching this file at all means spawning it, and
  the counters a second Node keeps never come back to the run that asked. What
  the command actually does lives in program.ts, measured there by the same
  suite. */

import process from "node:process";
import { makeProgram } from "./program.ts";

await makeProgram().parseAsync(process.argv);
