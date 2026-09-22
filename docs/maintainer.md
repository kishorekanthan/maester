# Maintainer process

This file records the maintainer's own bookkeeping. Contributors do not need
it; see [CONTRIBUTING.md](../CONTRIBUTING.md) instead.

## Trackers

The Jira project `MAES` is the maintainer's tracker of record and is private.
Every ticket carries **Why**, **What** including what is out of scope, and
**Acceptance criteria** checkable by a test or a named manual check.

Commits and PR titles cite the Jira key: `MAES-12: ...`. A GitHub issue number
may appear alongside it in the body, never instead of it. A public issue is
triaged into a MAES ticket before work starts, and the two are cross-linked.
The tickets that were mirrored into GitHub before this rule existed are closed,
each pointing at its MAES key.

## Architectural decisions

Past architectural decisions live on the `/wayfinder` map, issue #1 of the
private `kishorekanthan/maester-archive`. Read it before proposing anything
architectural — a question you are about to reopen may already be closed there
— but do not read it as a statement of what is in flight now, which is MAES.

## Publication

`kishorekanthan/maester` is seeded from a single reviewed squash. The archive
repository's history is not published, mirrored, or merged into it.
