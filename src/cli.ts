#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import process from "node:process";
import { makeProgram } from "./program.ts";

await makeProgram().parseAsync(process.argv);
