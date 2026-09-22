# Security

## Trust model

Maester only ever executes `<provider> do <declared-id> [item-id]`. The
provider contract carries no command strings anywhere — not in a provider's
JSON output, not in `~/.config/maester/config.json`. An action id must match
one the provider declared in its most recent report before Maester will run
it.

Providers are refused at load time unless the provider file **and** its
containing directory are owned by you and are not group- or world-writable —
the same check `ssh` and `sudo` apply to their own configuration files. The
check follows symlinks, so a link pointing at a world-writable file elsewhere
is refused too. A refused provider is shown in the panel with the reason
rather than silently skipped.

## What this does not protect against

A provider you chose to install runs with your privileges. Maester enforces
that the provider file is under your control before it will run it at all,
but it does not sandbox what a trusted provider does once invoked, and it
does not vet what a provider's `status`, `stream`, or `do` reports or does.
Installing a provider is the same trust decision as installing any other
executable you run yourself — review it before you symlink it into
`~/.config/maester/providers/`.

## No telemetry, no network calls

The app makes no network requests of its own and collects no telemetry. What
a provider does over the network is that provider's business, not the app's.

## Reporting a vulnerability

Report suspected vulnerabilities using GitHub's private vulnerability
reporting on this repository (the "Report a vulnerability" button under the
repository's Security tab), rather than a public issue. Do not include
exploit code that could affect other users' machines in a public report.
