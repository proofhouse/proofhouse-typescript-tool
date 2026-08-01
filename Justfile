set unstable := true
set positional-arguments := true

# Run [script] recipes under bash rather than the default sh. On Linux
# sh is dash, which lacks [[ ]], <<<, and set -o pipefail — constructs
# [script] recipes are free to rely on. macOS sh is bash, so a dash
# incompatibility would stay hidden locally until CI runs on Linux.
set script-interpreter := ['bash', '-eu']

# Build metadata. `date` is the *committer date* (UTC, ISO-8601), not
# build invocation time, so two builds of the same commit produce
# identical artifacts. `source_date_epoch` carries the same instant as a
# unix timestamp for downstream tooling that honors SOURCE_DATE_EPOCH;
# nothing consumes it yet, and the reproducible-build check that follows
# records where it does and does not apply. There is no version variable
# here: package.json holds the version and buildmeta reads it from there
# at run time.
#
# `--abbrev=7` / `--short=7` pin the abbreviated hash length so two
# checkouts of the same commit produce the same string. Without this,
# git uses `core.abbrev=auto`, whose length depends on object count
# (shallow clones, freshly-packed repos, and aged working copies all
# differ). 7 matches goreleaser's `.ShortCommit`.

commit := `git rev-parse --short=7 HEAD 2>/dev/null || echo ""`
date := `TZ=UTC git log -1 --format=%cd --date=format-local:%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown"`
source_date_epoch := `git log -1 --format=%ct 2>/dev/null || echo "0"`

# Default recipe
default: test

# --- Build ---

# Rewrite the generated module the version subcommand reads its commit
# and date from. TypeScript has no link step to inject them, and an
# import of a module that is not on disk cannot typecheck, so the file
# is committed carrying the fallbacks and this recipe overwrites it for
# the length of a build. Every recipe that calls it puts the committed
# copy back on the way out.
[script]
stamp:
    cat > src/generated/buildinfo.ts <<'EOF'
    // SPDX-License-Identifier: Apache-2.0
    // Copyright Authors of Proofhouse

    // The stamp recipe rewrites this file during a build and puts this copy back
    // afterwards. What is committed here are the unstamped fallbacks, so a plain
    // source checkout typechecks and runs without a build ever having happened.

    /** Short git SHA the build came from, empty when nothing stamped it. */
    export const COMMIT: string = "{{ commit }}";

    /** Calendar date of the build, "unknown" when nothing stamped it. */
    export const DATE: string = "{{ date }}";
    EOF

# Compile dist from the stamped tree. The trap fires whether or not the
# compile succeeds, so the emitted JavaScript carries the real commit
# and date while the working tree is left the way it was found.
[script]
build: stamp
    trap 'git restore src/generated/buildinfo.ts' EXIT
    node node_modules/tsc7/bin/tsc -p tsconfig.build.json

# Run the tool straight from source under Node's type stripping, with no
# build in between. Same stamp-and-restore handling as build.
[script]
run *args: stamp
    trap 'git restore src/generated/buildinfo.ts' EXIT
    node src/cli.ts "$@"

# Drop build output and return the generated module to its committed state
clean:
    rm -rf dist
    rm -f *.tsbuildinfo
    git restore src/generated/buildinfo.ts

# --- Test ---

# Run tests
test *args:
    node_modules/.bin/vitest run "$@"

# Typecheck the sources and the tests. tsc7 is named by path because
# both compilers in devDependencies ship a tsc binary and only one of
# them wins the .bin link, which would leave install order deciding
# which compiler rules on the code.
typecheck:
    node node_modules/tsc7/bin/tsc -p tsconfig.json

# --- Utilities ---

# Check that the two-compiler wiring is intact. typescript supplies the
# JS API that typed lint tooling loads, and tsc7, an alias of
# TypeScript 7, is the compiler the gates run. Both expected versions
# come out of package.json, so a dependency bump moves the pins and the
# assertions together instead of leaving them to drift apart.
[script]
doctor:
    want_api=$(node -p 'require("./package.json").devDependencies.typescript')
    have_api=$(node -p 'require("typescript").version')
    if [[ "$have_api" != "$want_api" ]]; then
        echo "typescript resolves to $have_api, package.json pins $want_api" >&2
        exit 1
    fi
    want_gate=$(node -p 'require("./package.json").devDependencies.tsc7.split("@").pop()')
    have_gate=$(node node_modules/tsc7/bin/tsc --version)
    if [[ "$have_gate" != "Version $want_gate" ]]; then
        echo "tsc7 reports '$have_gate', the alias pins typescript $want_gate" >&2
        exit 1
    fi
    echo "typescript $want_api (API), tsc7 $want_gate (gate)"
