// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { defineConfig, type ViteUserConfig } from "vitest/config";

// The config is a named `const` rather than an inline default export because
// `isolatedDeclarations` needs a written type on everything a module exports.
const config: ViteUserConfig = defineConfig({
  test: { include: ["tests/**/*.test.ts"] },
});

// biome-ignore lint/style/noDefaultExport: `vitest` reads a config module's default export.
export default config;
