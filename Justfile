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

# The tombi release this repository's config and its committed TOML
# formatting are verified against. tombi comes from Homebrew rather
# than the lockfile, so `check-tombi-version` weighs the local binary
# against this pin: a mismatch means a local format run may not land
# where the gate expects.

# renovate: datasource=github-releases depName=tombi-toml/tombi

tombi_version := "1.2.5"

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

    // The stamp recipe rewrites this file during a build and puts the committed
    // copy back afterwards. That copy carries the unstamped fallbacks, so a plain
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

# Prove that one commit packs to one tarball. The recipe clones the
# committed tree twice, hands each clone the working copy of the
# lockfile so both installs resolve the same versions, then installs,
# builds, and packs in each and compares the two tarballs by digest.
# Both clones sit on the same commit, so stamping puts identical values
# in both. pnpm's packer normalizes archive metadata on its own and
# reads nothing from SOURCE_DATE_EPOCH, which is why that variable
# exists here for parity with the sibling repositories and is not
# threaded into pack. What is left for a digest to disagree about is the
# compiled output, so this also stands as the running check that
# TypeScript 7 emits the same bytes every time it compiles the sources.
[script]
build-repro-check:
    first=$(mktemp -d)
    second=$(mktemp -d)
    trap 'rm -rf "$first" "$second"' EXIT
    for dir in "$first" "$second"; do
        git clone --quiet --no-hardlinks . "$dir"
        cp -f pnpm-lock.yaml "$dir/pnpm-lock.yaml"
        (cd "$dir" && pnpm install --frozen-lockfile && just build && pnpm pack)
    done
    sum_first=$(shasum -a 256 < "$first"/*.tgz)
    sum_second=$(shasum -a 256 < "$second"/*.tgz)
    if [[ "$sum_first" != "$sum_second" ]]; then
        echo "not reproducible: two packs of {{ commit }} differ" >&2
        exit 1
    fi
    echo "reproducible: two packs of {{ commit }} share sha256 ${sum_first%% *}"

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

# --- Format ---

# Rewrites in place. Pair with `fix-markdown` for semantic lint fixes.

# Format Markdown files (whitespace, list markers, code fence styles).
format-markdown *args:
    rumdl fmt {{ if args == "" { "." } else { args } }}

# Applies the layout biome.json settles: spaces, 100 columns, double quotes,
# imports in biome's order. Everything else biome has to say about a file
# comes from `lint-config`, which rewrites nothing.

# Format JSON, JS, and TS files in place via biome's formatter.
format-config *args:
    node_modules/.bin/biome format --write {{ if args == "" { "." } else { args } }}

# The in-place half of what `lint-toml` only reports on. Whitespace and
# style are all it rewrites: key order and array order stay as written,
# because tombi.toml switches schema-driven reordering off. Which files
# it walks is that config's call, not a path argument's.

# Format TOML files in place.
format-toml:
    tombi format

# --- Fix ---

# Complement to `format-markdown` (which only rewrites whitespace and
# ordering, not semantic lints).

# Apply rumdl's auto-fixable rules to Markdown files.
fix-markdown *args:
    rumdl check --fix {{ if args == "" { "." } else { args } }}

# --- Lint ---

# One name for every gate that reads the source tree, so a contributor
# and a merge check reach the same set without listing it out. Each
# gate that lands appends itself here; prose is the first of them.

# Run every linter that operates on the source tree.
lint: lint-prose lint-spelling lint-markdown lint-config lint-yaml lint-toml

# The glob keeps vale off files whose prose nobody here writes: the
# LICENSE and the generated changelog, vale's own synced styles, the
# scratch directory, the agent worktrees and the shared rules deployed
# under .claude/, installed packages and compiled output, and the
# coverage, report, and mutation scratch trees. COMMIT_AGENTMSG sits in
# the list too, because .vale.ini reads that draft under the stricter
# commit scope. Which of the remaining files get inspected, and under
# which rules, is .vale.ini's call.

# Lint prose in Markdown files and source comments via vale.
lint-prose *args:
    vale --output=proofhouse-agent.tmpl --glob='!{LICENSE,CHANGELOG.md,.vale/*,tmp/*,.claude/rules/*,.claude/worktrees/*,COMMIT_AGENTMSG,dist/*,node_modules/*,coverage/*,reports/*,.stryker-tmp/*}' {{ if args == "" { "." } else { args } }}

# Words this project uses that a dictionary would not carry live in
# .cspell-words.txt, and .cspell.jsonc says which files are worth
# reading at all. The binary comes out of node_modules by path: the
# gate weighs the tree against the version pinned in package.json,
# whatever cspell a machine may have on PATH. COMMIT_AGENTMSG stays
# out, so a message still being drafted cannot fail the tree.

# Check spelling across the tree.
lint-spelling *args:
    node_modules/.bin/cspell --config .cspell.jsonc --no-summary --no-progress --no-must-find-files --exclude COMMIT_AGENTMSG {{ if args == "" { "." } else { args } }}

# rumdl handles structural lints (heading style, list marker style,
# code fence style); vale handles prose.

# Lint Markdown files against the project's .rumdl.toml ruleset.
lint-markdown *args:
    rumdl check {{ if args == "" { "." } else { args } }}

# Biome reads the TypeScript sources and the JSON that configures them,
# reporting layout drift alongside its lint rules. The whole preset is on,
# so one pass covers correctness, style, complexity, and import order.
# Naming the executable under node_modules holds the gate to the pinned
# copy rather than to whatever a machine happens to have installed.

# Lint JSON, JS, and TS files via biome.
lint-config *args:
    node_modules/.bin/biome check --files-ignore-unknown=true {{ if args == "" { "." } else { args } }}

# --strict promotes every warning to a failure, so a run here lands on
# the same verdict a merge check would. Which rules apply is
# .yamllint.yaml's call, and it draws the walk's scope from .gitignore
# plus .yamllintignore. The second file exists for what the first misses:
# pnpm-lock.yaml is tracked, and its resolution lines run well past any
# column limit worth setting.

# Lint YAML files (configuration and workflow definitions).
lint-yaml *args:
    yamllint --strict {{ if args == "" { "." } else { args } }}

# tombi is the TOML gate every sibling repository runs. It reads what
# git tracks: the runtime pins today, its own config beside them, and
# whatever configuration arrives in that dialect later. Files with a
# known schema validate against the copy tombi embeds, and the rest
# still get syntax and style checks. --offline holds the run to those
# embedded copies so a merge check never waits on SchemaStore, and
# --error-on-warnings settles a warning the same way the rest of the
# chain does. The format pass runs first in --check --diff mode, which
# prints drift and leaves the file alone; format-toml is where a fix
# belongs. Neither line takes a path. Scope lives in tombi.toml, which
# is why this recipe is the one gate here without an *args default of
# the current directory.

# Lint and format-check every tracked TOML file.
lint-toml:
    tombi format --check --diff
    tombi lint --offline --error-on-warnings

# Advisory, not fatal, and outside `lint` for that reason. tombi moves
# on Homebrew's schedule rather than the lockfile's, which is workable
# so long as a drifted binary announces itself instead of quietly
# reformatting a file the gate then rejects.

# Warn when the local tombi differs from the verified release.
[script]
check-tombi-version:
    local=$(tombi --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ "${local}" != "{{ tombi_version }}" ]]; then
        echo "warning: local tombi ${local} != verified {{ tombi_version }}" >&2
        echo "         formatting may differ from what the gate expects" >&2
    else
        echo "tombi ${local} matches the verified release"
    fi

# --- Dependencies ---

# Check that pnpm-lock.yaml still matches the specifiers in
# package.json. The lockfile-only flag makes this a check and not an
# install: pnpm resolves, finds the lockfile out of date, and exits
# naming the specifier that moved, without writing node_modules or the
# lockfile itself. CI runs this on every pull request; contributors run
# `pnpm install` and commit the updated lockfile.
lock-check:
    pnpm install --frozen-lockfile --lockfile-only

# --- Utilities ---

# The styles named in .vale.ini's Packages list are downloaded under
# .vale/, which git does not track apart from the vocabulary. Run this
# after cloning, and again whenever that list moves.

# Sync Vale styles and dictionaries.
vale-sync:
    vale sync

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
