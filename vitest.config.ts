// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { configDefaults, defineConfig, type ViteUserConfig } from "vitest/config";

// The config is a named `const` rather than an inline default export because
// `isolatedDeclarations` needs a written type on everything a module exports.
const config: ViteUserConfig = defineConfig({
  // The erasable suite is written against `node:test` and runs under the
  // runtime alone, so the include glob has to be told to leave it behind. A
  // bare list here would replace vitest's own exclusions rather than add to
  // them, leaving `node_modules` and `dist` inside the walk.
  test: {
    include: ["tests/**/*.test.ts"],
    exclude: [...configDefaults.exclude, "tests/erasable/**"],
    // Files and tests alike arrive in a drawn order rather than the order
    // they were written in. A suite that only ever runs one way can come to
    // lean on that way without anyone noticing. Shuffling makes such quiet
    // coupling a failure while its cause is still close at hand. The seed
    // behind a draw prints beside every summary, a passing one included, and
    // `sequence.seed` is where that number goes to bring an order back.
    sequence: { shuffle: true },
    coverage: {
      provider: "v8",
      // Version 4 counts only the modules a run happened to load, so a source
      // file no test ever imports would sit outside the score rather than at
      // the bottom of it. Naming the tree here holds every file in the
      // denominator even when nothing reached it.
      include: ["src/**"],
      exclude: ["**/*.d.ts"],
      reporter: ["text", "lcov"],
      // Each file answers for itself. An average across the tree would let a
      // well-covered module carry one with no tests behind it.
      thresholds: {
        branches: 100,
        functions: 100,
        lines: 100,
        statements: 100,
        perFile: true,
      },
    },
  },
});

// biome-ignore lint/style/noDefaultExport: `vitest` reads a config module's default export.
export default config;
