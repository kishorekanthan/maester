# Contributing

## Build and test

```bash
./check.sh
```

builds the app, runs every suite in `tests/`, the complexity gate
(`swiftlint`), and the no-comments check, in that order. It must pass before a
pull request is reviewed; CI runs the same script.

To install the bundled providers and validate them against the contract:

```bash
./install.sh && ./maester-doctor
```

## The PR bar

1. `./check.sh` green: build clean with no new warnings, every suite in
   `tests/` passing, the complexity gate at 0 violations, no comments in code.
2. `./install.sh && ./maester-doctor` reports 0 failing.
3. A new or changed provider ships fixtures for its failure modes, not only
   its happy path.
4. A new `#available` guard adds a row to the feature ceiling table in
   `README.md` (see below).

## Hard rules

**No code comments.** Not explanatory, not section banners, not TODOs.
Documentation belongs in Markdown files (`CONTRACT.md`, `README.md`, files
under `docs/`, this file) or in the body of the pull request. Docstrings count
as comments and are covered by the same rule.

**No tautological tests.** A test that restates the implementation, asserts a
constant against itself, or mocks the thing under test and then checks the
mock, is not a test — delete it. If a test would still pass against a
deliberately broken implementation, it is tautological.

Example of what to avoid:

```swift
// Bad: the "expected" value is computed the same way the code computes it.
let result = worstState(of: providers)
XCTAssertEqual(result, providers.map { $0.state }.max())
```

Assert against a value captured independently of the code under test instead
— a hand-picked case (`[.ok, .warn, .error]` must yield `.error`), not a
restatement of the aggregation logic.

**Cyclomatic complexity is a standing gate.** New code must not exceed the
project's complexity threshold; the check runs alongside the rest of the
build, not as a matter of review judgment.

**Providers print one JSON document per line.** `status` prints exactly one
object and exits. `stream` prints one object per line, forever, and nothing
else on stdout — no partial writes, no pretty-printing across multiple lines,
no blank lines between objects. Diagnostics go to stderr.

## Writing and testing a provider

A provider is any executable that answers the contract in
[CONTRACT.md](CONTRACT.md): `status` with one JSON object, optionally `stream`
with one object per line forever, and `do <action-id> [item-id]` to perform
something it declared.

Check it before trusting it:

```bash
maester-doctor <name>
maester-doctor <name> --stream
```

`maester-doctor` validates the object against the contract, checks file and
directory permissions, and reports the `schema` your provider emits and
whether this build of Maester supports it.

## Requirements

Development targets macOS 15 or later on Apple Silicon; there is no Intel
build.

## The feature ceiling

Adding an `#available` guard adds a row to the feature ceiling table in
`README.md`. A version-dependent difference the user is not told about is
indistinguishable from a bug, and they have no way to find out which it is.
