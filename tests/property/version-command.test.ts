// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { test } from "@fast-check/vitest";
import { describe, expect, vi } from "vitest";

import type { BuildInfo } from "../../src/buildmeta.ts";
import { makeProgram } from "../../src/program.ts";
import { stamps } from "./stamps.ts";

// The rendering is what stands trial here, so the facts behind it come from a
// draw rather than from the checkout. A mock factory runs once while the
// draws keep arriving, which is what the holder below is for: the stand-in
// reads it fresh on every call.
const reported = vi.hoisted(() => ({ info: { version: "", commit: "", date: "unknown" } }));

vi.mock("../../src/buildmeta.ts", () => ({
  get: (): BuildInfo => reported.info,
}));

// The block ends in a newline, so splitting it leaves a fourth, empty part.
const VERSION_OUTPUT_PARTS = 4;

function versionOutput(): string {
  let out = "";
  const program = makeProgram();
  program.configureOutput({
    writeOut: (str: string): void => {
      out += str;
    },
  });
  program.parse(["version"], { from: "user" });
  return out;
}

describe("the version subcommand", () => {
  test.prop([stamps()])("prints any build facts as the same three lines", (info) => {
    reported.info = info;

    const lines = versionOutput().split("\n");

    expect(lines).toHaveLength(VERSION_OUTPUT_PARTS);
    expect(lines[0]).toBe(`proofhouse-typescript-tool ${info.version}`);
    expect(lines[1]).toBe(`commit: ${info.commit}`);
    expect(lines[2]).toBe(`date:   ${info.date}`);
    expect(lines[3]).toBe("");
  });
});
