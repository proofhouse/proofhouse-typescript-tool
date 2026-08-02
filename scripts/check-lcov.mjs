// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

// The merged report stands in for the whole matrix, and a merge that lost a
// slot on the way still reads as a valid file. This script asks the threshold
// question again of the merged numbers: every line, branch, and function a
// record declares has to carry a hit count, per file and across the report. A
// report holding no records fails as well, since an empty one would otherwise
// satisfy every comparison it is handed.

import { readFileSync } from "node:fs";
import process from "node:process";

// Each entry names one counter pair: what lcov calls the declared total, what
// it calls the reached total, and the word for them when the two disagree.
const COUNTERS = [
  { declared: "LF", reached: "LH", noun: "lines" },
  { declared: "BRF", reached: "BRH", noun: "branches" },
  { declared: "FNF", reached: "FNH", noun: "functions" },
];

const COUNT_LINE = /^(LF|LH|BRF|BRH|FNF|FNH):(\d+)$/;
const SOURCE_LINE = /^SF:(.+)$/;
const USAGE_EXIT = 2;

const failures = [];

function check(where, tally) {
  for (const { declared, reached, noun } of COUNTERS) {
    const found = tally.get(declared) ?? 0;
    const hit = tally.get(reached) ?? 0;
    if (found !== hit) {
      failures.push(`${where}: ${hit} of ${found} ${noun} covered`);
    }
  }
}

const [report] = process.argv.slice(2);
if (report === undefined) {
  process.stderr.write("usage: check-lcov.mjs <merged lcov file>\n");
  process.exit(USAGE_EXIT);
}

const totals = new Map();
let counts = new Map();
let source = "";
let records = 0;

for (const line of readFileSync(report, "utf8").split(/\r?\n/)) {
  const [, named] = SOURCE_LINE.exec(line) ?? [];
  const [, counter, count] = COUNT_LINE.exec(line) ?? [];
  if (named !== undefined) {
    source = named;
    counts = new Map();
  } else if (counter !== undefined) {
    counts.set(counter, Number(count));
  } else if (line === "end_of_record") {
    records += 1;
    check(source, counts);
    for (const [key, value] of counts) {
      totals.set(key, (totals.get(key) ?? 0) + value);
    }
  }
}

if (records === 0) {
  failures.push(`${report}: no coverage records`);
} else {
  check(`${report} across ${records} files`, totals);
}

if (failures.length > 0) {
  process.stderr.write(`${failures.join("\n")}\n`);
  process.exit(1);
}

process.stdout.write(`${report}: ${records} files fully covered\n`);
