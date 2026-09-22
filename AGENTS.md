# Working rules for agents

## No inline comments

**Write no comments in code.** Not explanatory comments, not section banners,
not "why" comments, not TODOs. Documentation belongs in Markdown files.

This is a hard rule, not a preference to weigh against readability. Only agents
work in this codebase; prose next to the code is cost without a reader. A
minimal comment layer will be added back deliberately, later.

Applies to new and modified code. Do not strip comments from code you are not
otherwise touching — the existing sources predate this rule and will be dealt
with separately.

Docstrings count as comments. A Python module, class or function docstring is
inline prose living in the code, and it is covered by this rule exactly as a
`#` comment is. The same goes for Swift `///` doc comments.

Not covered, because they are documentation rather than inline commentary:
`CONTRACT.md`, `README.md`, files under `docs/`, this file, and the bodies of
tickets and issues. Usage strings printed to a terminal are program output, not
comments, and stay.

## Raise correctness problems, do not file them under scope

If you find a bug while doing something else — data loss, a security hole, a
wrong result — say so plainly in your report and, where it is small and in
code you are already touching, fix it.

A list of test cases in a task is illustration, not a boundary. "It was not in
the enumerated cases" is not a reason to ship a defect you have seen. If fixing
it would genuinely widen the change too far, stop and report it rather than
leaving it silently in place.

## Naming and copy

No allusion to any fictional setting anywhere — code, docs, icon, UI copy,
commit messages. This is a deliberate constraint over potential IP conflict.
`maester` is used only in its plain sense of a record-keeper.

## The contract is a security boundary

The provider contract carries **no command strings**. Maester only ever
executes `<provider> do <declared-id>`, where the id matches one the provider
declared in its last report. No change may introduce a path by which
provider output or user config supplies a command to run.

Providers are refused unless the file and its directory are owned by the user
and are not group- or world-writable, following symlinks. Do not weaken this.

## Maester knows nothing domain-specific

The app renders whatever providers report. It must never gain knowledge of what
a particular provider does. Configuration may name a provider; it may never
name a capability inside one.

## The complexity gate is a ratchet at 5

`cyclomatic_complexity` fails at 5, and `check.sh` runs it against
`scripts/swiftlint-baseline.json`, which records the eight functions that were
already over that line when the threshold was lowered. Anything new above 5
fails the gate.

The baseline may only shrink. Never raise the threshold, add a baseline entry,
or reach for a `swiftlint:disable` comment to get past it — extract a helper.
Regenerate the file only when an entry has been refactored away, with
`swiftlint lint --config .swiftlint.yml --write-baseline scripts/swiftlint-baseline.json`,
and expect the count to go down.

## Where the work is tracked

Every change starts from a ticket carrying **Why**, **What** including what is
out of scope, and **Acceptance criteria** that are checkable by a test or a
named manual check.

[GitHub Issues](https://github.com/kishorekanthan/maester/issues) is the intake
path and the public record. Outside contributors file there, and an issue is
triaged into a ticket before work starts on it.

The maintainer additionally mirrors tickets into a private tracker and keeps a
private map of past architectural decisions. Those are maintainer bookkeeping;
nothing in them is needed to contribute, and a PR is never blocked on them.
Maintainer-side conventions live in [docs/maintainer.md](docs/maintainer.md).

## Commit authorship

Never add a `Co-Authored-By` trailer, and never name an agent, tool, or model in
a commit message or PR body. The repository owner is the sole author of record.

## The feature ceiling is part of the contract with the user

Adding an `#available` guard adds a row to the feature ceiling table in
`README.md`. A version-dependent difference the user is not told about is
indistinguishable from a bug, and they have no way to find out which it is.
