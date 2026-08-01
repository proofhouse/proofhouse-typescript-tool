// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { defineConfig, type ViteUserConfig } from "vitest/config";

// The config is a named `const` rather than an inline default export because
// `isolatedDeclarations` needs a written type on everything a module exports.
const config: ViteUserConfig = defineConfig({
  // The erasable suite is written against `node:test` and runs under the
  // runtime alone, so the include glob has to be told to leave it behind.
  test: { include: ["tests/**/*.test.ts"], exclude: ["tests/erasable/**"] },
});

// biome-ignore lint/style/noDefaultExport: `vitest` reads a config module's default export.
export default config;
