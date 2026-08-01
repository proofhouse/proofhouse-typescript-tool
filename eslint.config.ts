// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { type ConfigObject, defineConfig, globalIgnores } from "eslint/config";
import jsdoc from "eslint-plugin-jsdoc";
// The security plugin exports its configs by name under CommonJS and offers
// no default, so it comes in by name where the other three arrive whole.
import { configs as securityConfigs } from "eslint-plugin-security";
import tsdoc from "eslint-plugin-tsdoc";
import tseslint from "typescript-eslint";

type EslintPlugin = NonNullable<ConfigObject["plugins"]>[string];

// A named `const` carrying a written type, for the same reason vitest.config.ts
// has one: `isolatedDeclarations` rejects an inline default export.
const config: ConfigObject[] = defineConfig([
  // Compiled output, plus the scratch trees the coverage and mutation gates
  // write later. Everything left is what tsconfig.json already includes.
  globalIgnores(["dist", "coverage", "reports", ".stryker-tmp", "node_modules"]),
  {
    files: ["src/**/*.ts", "tests/**/*.ts", "*.config.ts"],
    extends: [
      // The type-aware halves of both presets. Their syntax-only counterparts
      // repeat rules `biome` already runs under its `all` preset, and a finding
      // with two owners gets answered twice.
      tseslint.configs.strictTypeCheckedOnly,
      tseslint.configs.stylisticTypeCheckedOnly,
      // Neither of the next two entries fits the array on its own. The
      // `jsdoc` configs come out of an index signature, so the value reads as
      // possibly absent, and the security plugin's published types still
      // describe the flat config through the older Linter interfaces. Each
      // cast names what the value is instead of widening what the array
      // holds.
      jsdoc.configs["flat/recommended-tsdoc-error"] as ConfigObject,
      securityConfigs.recommended as unknown as ConfigObject,
    ],
    // The tsdoc plugin declares its own rule interface, which predates the one
    // `eslint` publishes today. Same reasoning as the preceding casts.
    plugins: { tsdoc: tsdoc as unknown as EslintPlugin },
    languageOptions: {
      parserOptions: {
        // The service reads tsconfig.json for each file it sees, so the scope
        // of the typed rules follows that file's `include` rather than a second
        // list kept here.
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // A `switch` over a closed union has to spell out every member. The
      // option counts a `default` arm as covering the rest, which keeps the
      // rule quiet on a switch that already handles the whole union that way.
      "@typescript-eslint/switch-exhaustiveness-check": [
        "error",
        { considerDefaultExhaustiveForUnions: true },
      ],
      // Array.prototype.sort compares elements as text without one, which
      // orders 10 ahead of 9.
      "@typescript-eslint/require-array-sort-compare": "error",
      // TSDoc syntax errors in a doc comment, reported by the plugin that
      // reads the grammar itself rather than by the `jsdoc` rules around it.
      "tsdoc/syntax": "error",
      // Documentation is owed on what the package hands out, not on the
      // helpers behind it.
      "jsdoc/require-jsdoc": ["error", { publicOnly: true }],
      // The `useSingleJsDocAsterisk` rule in `biome` already answers for this,
      // and one finding wants one owner.
      "jsdoc/no-multi-asterisks": "off",
      // Blank lines between tags are the author's business; a blank line
      // between the description and the first tag isn't.
      "jsdoc/tag-lines": ["error", "any", { startLines: 1 }],
      // The rule reads every computed property access as a possible injection,
      // including a loop index into a local array. Its own documentation calls
      // the finding a starting point for review rather than a defect.
      "security/detect-object-injection": "off",
    },
  },
  {
    // Both files read the package manifest through a URL resolved against
    // their own location on disk. The rule fires on any argument that isn't a
    // string literal, so a path built that way reads to it like one a caller
    // chose. Waived here rather than tree-wide, so a read that really does
    // build its path from an argument still gets a hearing.
    files: ["src/buildmeta.ts", "tests/buildmeta.test.ts"],
    rules: { "security/detect-non-literal-fs-filename": "off" },
  },
]);

// biome-ignore lint/style/noDefaultExport: `eslint` reads a config module's default export.
export default config;
