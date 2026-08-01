// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

import { Command } from "commander";

import { get } from "./buildmeta.ts";

/**
 * Build the command surface of the tool.
 *
 * Callers get the program before it parses anything, so tests can drive it in
 * process. Version reporting sits in a subcommand rather than a flag here,
 * matching the other reference tools in the organization.
 *
 * @returns A program with its commands registered and no argument list read.
 */
export function makeProgram(): Command {
  const program = new Command();

  program
    .name("proofhouse-typescript-tool")
    .description("Reference CLI for the Proofhouse TypeScript tool reference repository.");

  program
    .command("version")
    .description("Print version, commit, and build date.")
    .action(() => {
      const info = get();
      const text =
        `proofhouse-typescript-tool ${info.version}\n` +
        `commit: ${info.commit}\n` +
        `date:   ${info.date}\n`;
      // Writing through the program's configured output, rather than straight
      // to the console, is what lets a test collect this text in process.
      program.configureOutput().writeOut?.(text);
    });

  return program;
}
