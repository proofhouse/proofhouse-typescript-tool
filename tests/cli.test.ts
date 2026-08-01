// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { spawnSync } from "node:child_process";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { CommanderError } from "commander";
import { beforeAll, describe, expect, it } from "vitest";
import { get } from "../src/buildmeta.ts";
import { makeProgram } from "../src/program.ts";

const NAME_LINE = /^proofhouse-typescript-tool /;
const COMMIT_LINE = /^commit: /;
const DATE_LINE = /^date: {3}/;

// The version output ends in a newline, so splitting it leaves a fourth,
// empty part.
const VERSION_OUTPUT_PARTS = 4;

// Compiling the whole program takes longer than the default timeout `vitest`
// allows a hook, especially on the first run in a fresh checkout.
const BUILD_TIMEOUT_MS = 60_000;

interface Result {
  readonly out: string;
  readonly err: string;
  readonly error: CommanderError | undefined;
}

// Drive the program in process. `exitOverride` turns the exit paths into a
// throw, and the output configuration collects both streams.
function run(args: readonly string[]): Result {
  let out = "";
  let err = "";
  const program = makeProgram().exitOverride();
  program.configureOutput({
    writeOut: (str: string): void => {
      out += str;
    },
    writeErr: (str: string): void => {
      err += str;
    },
  });

  try {
    program.parse(args, { from: "user" });
  } catch (error) {
    if (!(error instanceof CommanderError)) {
      throw error;
    }
    return { out, err, error };
  }
  return { out, err, error: undefined };
}

function expectedVersionOutput(): string {
  const info = get();
  return (
    `proofhouse-typescript-tool ${info.version}\n` +
    `commit: ${info.commit}\n` +
    `date:   ${info.date}\n`
  );
}

describe("the version subcommand", () => {
  it("prints the build metadata as three lines", () => {
    const result = run(["version"]);
    expect(result.error).toBeUndefined();
    expect(result.out).toBe(expectedVersionOutput());
  });

  it("labels the lines the way the sibling tools do", () => {
    const lines = run(["version"]).out.split("\n");
    expect(lines).toHaveLength(VERSION_OUTPUT_PARTS);
    expect(lines[0]).toMatch(NAME_LINE);
    expect(lines[1]).toMatch(COMMIT_LINE);
    expect(lines[2]).toMatch(DATE_LINE);
  });
});

describe("the command surface", () => {
  it("refuses a command it does not know", () => {
    const result = run(["nope"]);
    expect(result.error?.exitCode).toBe(1);
    expect(result.err).toContain("unknown command 'nope'");
  });

  it("answers a bare invocation with help", () => {
    const result = run([]);
    // Commander treats the missing subcommand as a usage error: help goes to
    // the error stream and the exit code is 1, where the Python twin's `typer`
    // app reports 2. Each framework picks its own number here.
    expect(result.error?.exitCode).toBe(1);
    expect(result.err).toContain("Usage:");
    expect(result.err).toContain("version");
  });

  it("offers no version flag alongside the version command", () => {
    const result = run(["--help"]);
    expect(result.out).toContain("Usage:");
    expect(result.out).not.toContain("--version");
  });
});

describe("the built entry point", () => {
  const root = new URL("..", import.meta.url);

  beforeAll(() => {
    const build = spawnSync(
      process.execPath,
      ["node_modules/tsc7/bin/tsc", "-p", "tsconfig.build.json"],
      { cwd: fileURLToPath(root), encoding: "utf8" },
    );
    // A hook reports a failure by throwing. An assertion here would be
    // recorded against whichever test happened to run next.
    if (build.status !== 0 || build.stdout !== "" || build.stderr !== "") {
      throw new Error(`compiling dist did not succeed quietly: ${build.stdout}${build.stderr}`);
    }
  }, BUILD_TIMEOUT_MS);

  it("runs from the emitted JavaScript", () => {
    // The compiler rewrites the .ts import specifiers on the way out, so this
    // also proves dist/cli.js finds dist/program.js once the shebang file is
    // no longer TypeScript.
    const entry = fileURLToPath(new URL("dist/cli.js", root));
    const result = spawnSync(process.execPath, [entry, "version"], { encoding: "utf8" });
    expect(result.status).toBe(0);
    expect(result.stdout).toBe(expectedVersionOutput());
  });
});
