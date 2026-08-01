set unstable
set positional-arguments

# Run [script] recipes under bash rather than the default sh. On Linux
# sh is dash, which lacks [[ ]], <<<, and set -o pipefail — constructs
# [script] recipes are free to rely on. macOS sh is bash, so a dash
# incompatibility would stay hidden locally until CI runs on Linux.
set script-interpreter := ['bash', '-eu']

# Locate a Docker-compatible container runtime. Probe PATH first, then
# well-known install locations so the recipe still works inside agentic
# harnesses or sandboxes that strip /usr/local/bin from PATH. Override by
# setting CONTAINER_RUNTIME in the environment.
#
# The continuation lines of the `for` list below hang under the first
# candidate path rather than on a two-space grid, which is what shell
# style calls for and what `lint-editorconfig` would otherwise reject
# under this file's indent_size = 2. Exempt just that span rather than
# re-indent a block the sibling repos carry verbatim.
# editorconfig-checker-disable
container_runtime := env("CONTAINER_RUNTIME", `bash -c '
    docker_path=$(command -v docker 2>/dev/null || true)
    podman_path=$(command -v podman 2>/dev/null || true)
    for p in "$docker_path" \
             /usr/local/bin/docker \
             /opt/homebrew/bin/docker \
             /Applications/Docker.app/Contents/Resources/bin/docker \
             "$HOME/.orbstack/bin/docker" \
             "$HOME/.rd/bin/docker" \
             "$podman_path" \
             /opt/podman/bin/podman; do
        if [ -n "$p" ] && [ -x "$p" ]; then echo "$p"; exit 0; fi
    done
    echo docker
'`)

# editorconfig-checker-enable

# Shared container-run prefix. DOCKER_CONFIG points at a fresh empty
# directory so docker skips the osxkeychain credential helper (public
# Docker Hub pulls don't need it, and sandboxed environments can't
# always reach the helper binary). PATH gets the runtime's directory
# prepended for cases where docker itself isn't on the calling shell's
# PATH. Shell substitutions evaluate at recipe-run time, not
# Justfile-parse time.

docker_run := 'DOCKER_CONFIG="$(mktemp -d)" PATH="$(dirname ' + container_runtime + '):$PATH" ' + container_runtime + ' run --rm'

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

# actionlint version pin. The upstream image bundles actionlint and the
# shellcheck it shells out to at a known version, and actionlint has no
# first-party npm package for devDependencies to carry, so a Docker
# image pinned by digest stands in for a lockfile entry. Renovate reads
# the version + digest pair below through the comment marker (the shared
# Justfile customManager from the org's renovate presets).

# renovate: datasource=docker depName=rhysd/actionlint

actionlint_version := "1.7.12"
actionlint_image := "docker.io/rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667"

# actionlint invocation. Mounts the repo read-only at /repo with
# -w /repo so actionlint finds .github/workflows/.

actionlint := docker_run + ' -v "$(pwd):/repo:ro" -w /repo ' + actionlint_image

# Default recipe
default: test

# --- Setup ---

# What a fresh clone runs before anything else here works. Safe to run
# again at any point: Homebrew skips formulae already present, the
# style sync re-fetches against whatever .vale.ini names today, and the
# hook install overwrites .git/hooks with the current set. The runtime
# is out of scope for it, since mise.toml pins Node and the
# packageManager field in package.json routes pnpm.

# Set up the development environment.
setup: install-brew install-tools prek-install

# Install Homebrew dependencies from Brewfile.
install-brew:
    brew bundle check || brew bundle install

# Today that means Vale's synced style packages; grows as new
# sync-style tools land.

# Refresh non-brew tooling.
install-tools:
    vale sync

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

# A second, much smaller suite that runs on the runtime alone: no vitest,
# no transform, nothing between the sources and Node. What it proves is
# that the tree is erasable syntax the whole way down, since a stray
# enum or parameter property would stop the run before any assertion.
# vitest excludes this directory for that reason. Node globs the pattern
# itself, so it stays quoted rather than handed to the shell.

# Run the smoke suite as raw TypeScript under Node's type stripping.
test-erasable:
    node --test "tests/erasable/**/*.test.ts"

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
# comes from `lint-biome`, which rewrites nothing.

# Format JSON, JS, and TS files in place via biome's formatter.
format *args:
    node_modules/.bin/biome format --write {{ if args == "" { "." } else { args } }}

# The in-place half of what `lint-toml` only reports on. Whitespace and
# style are all it rewrites: key order and array order stay as written,
# because tombi.toml switches schema-driven reordering off. Which files
# it walks is that config's call, not a path argument's.

# Format TOML files in place.
format-toml:
    tombi format

# The rewriting half of `lint-just`, which reports and stops there. A
# gate that reformatted the file underneath the contributor would hide
# the edit it made, so the two stay apart, the way `format` and
# `lint-biome` do. `just --fmt` is an unstable feature still, and both
# recipes pass the flag rather than lean on the `set unstable` at the
# top of this file, so neither stops working if that setting goes.

# Rewrite this Justfile in just's own canonical format.
format-just:
    just --fmt --unstable

# --- Fix ---

# biome settles lint findings and layout in the same pass, so unlike the
# ruff pairing the sibling repositories run there is no formatter call to
# follow this one with. Only the fixes biome considers safe get applied.
# Anything else it finds stays for a human to answer.

# Fix biome lint findings and reformat what they touch.
fix *args:
    node_modules/.bin/biome check --write --files-ignore-unknown=true {{ if args == "" { "." } else { args } }}

# Complement to `format-markdown` (which only rewrites whitespace and
# ordering, not semantic lints).

# Apply rumdl's auto-fixable rules to Markdown files.
fix-markdown *args:
    rumdl check --fix {{ if args == "" { "." } else { args } }}

# --- Lint ---

# The source-language slice of `lint` below, held apart so that working
# through a TypeScript change means rerunning these gates alone rather
# than the whole tree-wide text sweep. A later gate over TypeScript
# appends itself to this list. Nothing here but dependencies.

# Run every TypeScript-flavored lint gate.
lint-ts-all: lint-biome typecheck lint-eslint lint-deadcode lint-deadcode-production lint-dup-code

# One name for every gate that reads the source tree, so a contributor
# and a merge check reach the same set without listing it out. The
# TypeScript gates arrive as a group at the head; the text and config
# gates that follow read the tree whatever language wrote it.

# Run every linter that operates on the source tree.
lint: lint-ts-all lint-prose lint-spelling lint-markdown lint-yaml lint-toml lint-just lint-editorconfig

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
# --error-on-warnings settles a warning the same way `lint-yaml` and
# `lint-toml` settle theirs. Several rules in the preset land at warning
# severity by default (useConst among them), and without the flag biome
# prints those findings and still exits 0.

# Lint JSON, JS, and TS files via biome.
lint-biome *args:
    node_modules/.bin/biome check --error-on-warnings --files-ignore-unknown=true {{ if args == "" { "." } else { args } }}

# Rules that ask the compiler what a name means, rather than reading one
# file's syntax. That is what lets them speak to a promise nobody
# awaited, a condition whose answer was settled before it ran, or a
# `switch` that forgot a member of its union. biome.json turns
# noUnnecessaryConditions and useAwait off because both findings belong
# to a checker holding the types, and one finding wants one owner. The
# run takes no path argument: the parser service reads tsconfig.json,
# and eslint.config.ts names the same three roots that file includes.
# A warning fails the run alongside an error, which is how a disable
# comment left behind after its finding went away becomes a failure.

# Lint TypeScript against the type-aware eslint rule set.
lint-eslint:
    node_modules/.bin/eslint . --max-warnings=0

# biome and the compiler each answer for a name where it is written. An
# export nothing anywhere imports still reads as fine to both. knip
# walks the import graph outward from the entry points and reports what
# nothing reaches: a whole file, one export, a type, a package listed in
# the manifest. Dead code is what the sibling Python repositories hand
# to vulture.
#
# knip.json carries the two settings this tree needs. It names
# src/cli.ts as the shipping entry and adds the type-assertion files
# under tests, which nothing imports by design. Its ignore list holds
# the packages recipes here run by path rather than import: biome,
# cspell, the clone detector, and the compiler that gates the sources.

# Report files, exports, and dependencies nothing reaches.
lint-deadcode:
    node_modules/.bin/knip

# The same walk from the shipping entry alone. Test files stop counting
# as roots, so an export reached only from the suite reads as dead
# rather than as public surface. Keeping this beside the everyday pass
# means the two views have to agree while a change is still local,
# instead of disagreeing later in a merge check.

# Report dead code across the packaged surface alone.
lint-deadcode-production:
    node_modules/.bin/knip --production

# Every gate above reads a name where it was written or follows an
# import to where it leads. A block of logic pasted into a second file
# breaks neither rule, and each copy then has to be found again the
# next time the logic changes. jscpd hashes windows of tokens across
# the tree and reports the pairs that match. pylint's similarities
# checker holds this slot in the sibling Python repositories.
#
# No config file: the flags read better beside the reason for them.
# --threshold names the share of duplicated lines the run tolerates,
# and 0 turns a single clone into a failure. --min-tokens is where a
# clone starts counting. 50 is jscpd's own default, written out so a
# release that moves it has to move this line too. Scope arrives as
# arguments because a clone spanning the sources and the suite is
# worth the same look as one inside either.

# Report token sequences duplicated across the sources and the suite.
lint-dup-code:
    node_modules/.bin/jscpd --threshold 0 --min-tokens 50 src tests

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

# Report drift and fail without touching the file. Nothing else in the
# chain reads this one's layout — biome, rumdl, yamllint, and tombi
# each answer for a different language — so absent this gate the
# Justfile would be the last config in the tree formatted by hand.
# `format-just` is where a fix belongs; see it for why --unstable is
# spelled out.

# Check this Justfile against just's own formatter in --check mode.
lint-just:
    just --fmt --check --unstable

# Charset, line endings, final newline, trailing whitespace, and both
# the tab-versus-space indent style and the indent width. .editorconfig
# has sat here read by editors and by nothing that could fail a merge;
# this is what makes it binding. Given no paths the checker walks what
# git tracks, so installed packages, compiled output, and Vale's synced
# style packages fall outside the run already.
# .editorconfig-checker.json names the latter two again, for a caller
# that does pass paths, and adds the changelog, whose layout belongs to
# the tool that writes it. Upstream ships a short `ec` alias in its
# release archives; the Homebrew formula builds the long name alone, so
# the recipe spells it out.

# Enforce .editorconfig with editorconfig-checker.
lint-editorconfig:
    editorconfig-checker

# actionlint walks `.github/workflows/` by default, parses each
# workflow, and flags unknown actions, mis-typed expressions,
# shellcheck issues inside `run:` blocks, and SHA-pin drift.
# Complements `lint-yaml` (which checks YAML structure) with
# workflow-shape rules yamllint can't see. Pinned Docker image;
# Renovate bumps the version + digest via the shared Justfile
# customManager.

# Lint GitHub Actions workflow files via actionlint.
lint-workflows:
    {{ actionlint }}

# Running the same gates the commit-msg hook runs surfaces message
# problems while iterating rather than at commit time. Reads the draft
# from the repo-root COMMIT_AGENTMSG file (gitignored; see AGENTS.md for
# the workflow) and runs the commit-msg stage through prek, which fires
# the four shared hooks from proofhouse/pre-commit-hooks:
# commit-trailers, commitlint, vale-commit-msg, and cspell-commit-msg.
# The real gate stays the prek commit-msg hook on .git/COMMIT_EDITMSG;
# this recipe only mirrors it. Commit the validated draft with
# `git commit -F COMMIT_AGENTMSG`.

# Pre-validate a drafted commit message against the commit-msg gates.
lint-commit-msg:
    prek run --stage commit-msg --commit-msg-filename COMMIT_AGENTMSG

# --- Dependencies ---

# Check that pnpm-lock.yaml still matches the specifiers in
# package.json. The lockfile-only flag makes this a check and not an
# install: pnpm resolves, finds the lockfile out of date, and exits
# naming the specifier that moved, without writing node_modules or the
# lockfile itself. CI runs this on every pull request; contributors run
# `pnpm install` and commit the updated lockfile.
lock-check:
    pnpm install --frozen-lockfile --lockfile-only

# The pnpm version is written down twice: package.json routes the package
# manager from it, and mise.toml installs the binary a shell picks up.
# Renovate groups the two files into one pull request, so the pair moves
# together on its own. What is left is a hand edit to one of them, which
# this catches. Advisory rather than a gate, since a disagreement here
# breaks nothing until the next install.

# Check that package.json and mise.toml pin the same pnpm.
[script]
check-tool-pins:
    manifest=$(node -p 'require("./package.json").packageManager.split("+")[0].split("@")[1]')
    mise=$(grep -E '^pnpm *= *"' mise.toml | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    if [[ "$manifest" != "$mise" ]]; then
        echo "pnpm pins disagree: packageManager $manifest, mise.toml $mise" >&2
        exit 1
    fi
    echo "pnpm $manifest pinned consistently in package.json and mise.toml"

# --- Utilities ---

# The styles named in .vale.ini's Packages list are downloaded under
# .vale/, which git does not track apart from the vocabulary. Run this
# after cloning, and again whenever that list moves.

# Sync Vale styles and dictionaries.
vale-sync:
    vale sync

# Run pre-commit hooks on changed files (the everyday invocation).
prek:
    prek

# Useful after a hook config change or before a release sweep.

# Run pre-commit hooks on every file in the tree.
prek-all:
    prek run --all-files

# The hooks cover commit-msg, pre-commit, and pre-push. `just setup`
# runs this automatically; it stays a separate recipe so contributors
# can re-install the hooks (which modify .git/) without re-running the
# whole setup.

# Install the project's pre-commit hooks.
prek-install:
    prek install -t commit-msg -t pre-commit -t pre-push

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

# `cog changelog` emits Markdown without an H1, so the pipeline prepends
# one and writes the file before linting it in place: rumdl matches the
# CHANGELOG.md per-file-ignores in .rumdl.toml (which disable MD024 for
# the repeated version headings) against on-disk paths, not stdin.

# Generate the full CHANGELOG.md from Conventional Commit history.
generate-changelog:
    cog changelog | { echo "# Changelog"; cat; } > CHANGELOG.md
    rumdl check --fix CHANGELOG.md

# Useful during release prep to see what `cog changelog` will emit
# before committing the regeneration.

# Preview the changelog entries since the last tagged release.
preview-changelog:
    cog changelog --at $(git describe --tags)..HEAD -t full_hash | rumdl check -d MD041 --fix --stdin

# Output goes to stdout; pipe to a file or paste into the GitHub
# release body.

# Generate release notes for a version, or for HEAD if none is given.
[script]
generate-release-notes version="":
    v=$([[ -n "{{ version }}" ]] && echo "v{{ version }}" || echo "..$(git rev-parse HEAD)")
    cog changelog --at $v -t full_hash | rumdl check -d MD024,MD041 --isolated --fix --stdin
