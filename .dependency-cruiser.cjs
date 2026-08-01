// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

// depcruise reads its config through `require`, so this file stays CommonJS
// while everything else in the tree is a module. A script loaded that way runs
// in sloppy mode unless it opts out, which every other file here gets for free
// by being a module.

"use strict";

/** @type {import("dependency-cruiser").IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: "no-circular",
      comment:
        "Modules that reach each other through a chain of imports have no order in which " +
        "one of them can be read, tested, or loaded ahead of the other. Break the cycle by " +
        "moving what both sides want into a module of its own.",
      severity: "error",
      from: {},
      to: { circular: true },
    },
    {
      name: "no-orphans",
      comment:
        "A module nothing imports and that imports nothing is either the start of work that " +
        "stalled or the remains of work that ended. The entry point below is neither, since " +
        "the manifest names it and no source file is meant to.",
      severity: "error",
      from: { orphan: true, pathNot: ["^src/cli[.]ts$"] },
      to: {},
    },
    {
      name: "no-unreachable-from-entry",
      comment:
        "Every source module has to sit on some import path out of the shipping entry point. " +
        "A module the walk never arrives at ships in the package and runs nowhere.",
      severity: "error",
      from: { path: "^src/cli[.]ts$" },
      to: { path: "^src", reachable: false },
    },
  ],
  // No layer rules here. This package is three modules deep with one edge
  // direction through it, cli to program to buildmeta, and reachability from
  // the entry point already answers for that shape. Order the layers once the
  // module count grows past what one rule can hold in view. The sibling
  // library carries the layered contracts today.
  options: {
    // Compiled output and installed packages hold copies of the sources whose
    // edges say nothing about how this tree is written.
    exclude: { path: "node_modules|dist|coverage" },
    // Type-only imports count as edges. Left out, a module reached for its
    // types alone would read as unreachable and a cycle running through a
    // type would go unreported.
    tsPreCompilationDeps: "specify",
    // Resolution follows the same compiler settings the gates do, which is
    // what lets the `.ts` specifiers this tree writes resolve here at all.
    tsConfig: { fileName: "tsconfig.json" },
  },
};
