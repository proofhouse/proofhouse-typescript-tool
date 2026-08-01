// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { defineConfig, type ViteUserConfig } from "vitest/config";

// The config is a named `const` rather than an inline default export because
// `isolatedDeclarations` needs a written type on everything a module exports.
const config: ViteUserConfig = defineConfig({
  test: { include: ["tests/**/*.test.ts"] },
});

export default config;
