# Launch communication: Maester v0.1.0

Drafts for announcing the first public release. Every claim below is backed by
the README, CHANGELOG or `docs/performance.md`; keep it that way when editing.

**Links**

- Repo: https://github.com/kishorekanthan/maester
- Release: https://github.com/kishorekanthan/maester/releases/latest
- Hero image: `docs/images/social-preview.png`
- Demo: `docs/images/panel-demo.gif`
- Provider demo: `docs/images/writing-a-provider.svg`

**Slogan:** "Eyes on your Mac. Never on you." Use it as the opener or closer, and
always pair it with the concrete fact behind it: no telemetry, and no network
requests from the app itself (third-party providers you add are their own
business, per the README).

**Brand type:** Bricolage Grotesque (SIL OFL) for headlines, JetBrains Mono for
code and readouts. The font files are in `docs/social/animation/src/fonts/`.

**Logo animation** (in `docs/social/animation/`, details in its README)

| File | Use it for |
| --- | --- |
| `maester-glance-16x9.mp4` | X main post, Reddit video post |
| `maester-glance-1x1.mp4` | LinkedIn main post (square takes more feed space) |
| `*-silent.mp4` | Anywhere that autoplays muted and ignores the sound |
| `maester-loop.gif` | README header, so HN visitors see it on click-through |
| `poster-16x9.png`, `poster-1x1.png` | Thumbnails and link previews |

**Social media images** (in `docs/social/images/`)

| File | Size | Use it for |
| --- | --- | --- |
| `hero.png` | 1600×900 | Slogan plus the dark panel. Bluesky, Mastodon, LinkedIn carousel |
| `demo-16x9.mp4` | 1600×900, 17.6 s | The real app in use. Second post on X, LinkedIn comment. Opens on the live panel, so the thumbnail isn't an empty desktop |
| `demo-16x9.gif` | 960×540, 9.5 s, 2.5 MB | Same demo, one loop, for Bluesky, Mastodon, Reddit, Slack and Discord |
| `square.png` | 1080×1080 | Slogan plus the light panel. LinkedIn carousel, Instagram, Reddit thumbnail |
| `provider.png` | 1600×900 | Thread post about providers, HN/dev audience |
| `principles.png` | 1600×900 | Thread post about cost and privacy |

Also usable as they are: `docs/images/panel-demo.gif` (Reddit, Mastodon),
`panel-light.png` / `panel-dark.png`, `menubar-states.png`.

**Key messages** (use one or two per post, not all)

1. Quit or force-quit a hung app from the menu bar. No terminal, no Dock icon.
2. CPU, GPU, memory, disk and running apps, live, in one panel.
3. One glyph = the worst state across everything, so one glance answers "does anything need me?"
4. Extensible: a provider is any executable that prints JSON. Monitoring a dev server or a CI queue is a shell script, not an app change.
5. Cheap and private: 0.013% average idle CPU (max 0.4%), no telemetry, no network requests.
6. Free and open source (MIT). macOS 15+, Apple Silicon.

**Say up front, don't bury:** the build is ad-hoc signed and not notarized, so
first launch needs System Settings → Privacy & Security → Open Anyway. It is
Apple Silicon only.

---

## X / Twitter

**Main post** (attach `animation/maester-glance-16x9.mp4`)

> Eyes on your Mac. Never on you. 👀
>
> Maester 0.1.0 is out: a macOS menu bar app that shows CPU, GPU, memory, disk and every running app live, and lets you quit or force-quit a hung app in one click.
>
> Free, open source, no telemetry.
>
> github.com/kishorekanthan/maester

**Thread**

> 2/ [attach `social/images/demo-16x9.mp4`] Here's the real thing. Hover any app for Open, Quit and Force quit.

> 3/ [attach `menubar-states.png`] The menu bar glyph is the worst state across everything Maester watches. One glance tells you whether anything needs you.

> 4/ It doesn't know anything about any particular domain. It renders whatever "providers" report. A provider is any executable that prints one line of JSON, so a dev server, launchd job or CI queue monitor is a shell script. [attach `social/images/provider.png`]

> 5/ [attach `social/images/principles.png`] "Never on you" is literal: no telemetry, and the app makes no network requests. Idle cost is 0.013% CPU on average, 0.4% at peak, over a 60s sample. Method is in docs/performance.md.

> 6/ macOS 15+, Apple Silicon. It isn't notarized yet, so the first launch needs Privacy & Security → Open Anyway. Feedback and providers welcome 🙏

## Bluesky (≤300 chars)

Attach `hero.png` (or the 16:9 animation).

> Eyes on your Mac. Never on you.
>
> Maester 0.1.0: a macOS menu bar app for CPU, GPU, memory, disk and running apps, with one-click force quit for hung apps. Extend it with any script that prints JSON. MIT, no telemetry.
>
> github.com/kishorekanthan/maester

## Mastodon (≤500 chars)

Attach `social/images/demo-16x9.gif` (alt text: "Opening the Maester panel from the menu bar, values updating live, and hovering a row to reveal Open, Quit and Force quit").

> Released Maester 0.1.0, a small macOS menu bar app. Eyes on your Mac, never on you.
>
> • Live CPU, GPU, memory, disk and running apps
> • Quit or force-quit a hung app from the panel
> • One glyph shows the worst state across everything
> • Add your own monitors: a "provider" is any executable that prints JSON
> • ~0.01% idle CPU, no telemetry, no network calls
>
> macOS 15+, Apple Silicon, MIT.
> https://github.com/kishorekanthan/maester
>
> #macOS #OpenSource #MacApps #Swift

## LinkedIn

Attach `animation/maester-glance-1x1.mp4`. Put `demo-16x9.mp4` in the first comment to show the real app, or post `hero.png` + `square.png` as a carousel instead.

> Eyes on your Mac. Never on you.
>
> I've released Maester 0.1.0, a free, open-source macOS menu bar app.
>
> It started from a small annoyance. When an app hangs, the fix is buried: open Activity Monitor, find the process, force quit. Maester keeps CPU, GPU, memory, disk and running apps one click away in the menu bar and lets you quit or force-quit from there.
>
> The design decision I'm happiest with is that the app knows nothing domain-specific. It renders whatever "providers" report through a fixed JSON contract. A provider can be any executable in any language. Two ship with it (the Mac itself and running apps), and watching a dev server, a launchd job or a CI queue takes a shell script, not a new app release.
>
> A few numbers and principles:
> • Idle self-cost averages 0.013% CPU (measured, method in the repo)
> • No telemetry and no network requests from the app. That's the "never on you" part
> • Supervised providers: a stalled stream restarts with backoff
> • MIT licensed
>
> Requires macOS 15+ on Apple Silicon.
>
> 👉 https://github.com/kishorekanthan/maester
>
> Feedback is welcome, and so are providers you'd like to see.
>
> #macOS #OpenSource #Swift #DeveloperTools

## Hacker News

**Title:** `Show HN: Maester – a macOS menu bar monitor you extend with scripts that print JSON`

**First comment (post right after submitting):**

> Hi HN, I built Maester because force-quitting a hung app always meant a trip to Activity Monitor. It's a menu bar item plus a panel showing CPU, GPU, memory, disk and running apps, with Quit / Force quit on each app.
>
> The app itself knows nothing domain-specific. Everything in the panel comes from "providers": executables in ~/.config/maester/providers that answer `status` with one line of JSON, or stream updates. The two bundled providers are zsh and read local state only (vm_stat, a single long-lived iostat, ps, df). The contract is in CONTRACT.md, and `maester-doctor` validates a provider's output.
>
> Things I cared about:
> - Idle cost: 0.013% average CPU over a 60s sample (docs/performance.md)
> - No telemetry, no network calls from the app
> - Numbers say what they measure. The README has a table of exactly what "Memory", "Apps memory" and so on mean, and a metric that fails to parse is omitted, not shown as zero.
>
> Caveats: Apple Silicon and macOS 15+ only, and it isn't notarized yet, so first launch needs Privacy & Security → Open Anyway (or build from source with ./build.sh).
>
> I'd love feedback on the provider contract especially.

## Reddit (r/macapps)

**Title:** `[Open Source] Maester: menu bar monitor for CPU/GPU/memory/apps with one-click force quit, extensible with shell scripts`

> Free (MIT), no telemetry, no account.
>
> **What it does**
> - Live CPU, GPU, memory, disk and running apps in a menu bar panel
> - Hover an app → Open / Quit / Force quit
> - The menu bar icon shows the worst state across everything, so you notice a hung app without opening anything
> - Add your own sections with any script that prints JSON (git status, dev servers, CI…)
>
> **Honest caveats**
> - Apple Silicon, macOS 15+
> - Not notarized yet: on first launch click Done, then System Settings → Privacy & Security → Open Anyway
>
> Download the .dmg from Releases: https://github.com/kishorekanthan/maester/releases/latest
>
> Eyes on your Mac, never on you. Happy to answer questions. Screenshots/GIF below.

(Attach `social/images/demo-16x9.gif` or `panel-demo.gif` plus `panel-light.png` and `panel-dark.png`. The logo animation also works as a separate video post. Check the
subreddit's self-promotion rules first. r/MacOS and r/swift are alternatives;
tailor the angle, don't cross-post the same text.)

---

## Posting checklist

- [ ] Release v0.1.0 is published with `.dmg` and `.zip` attached
- [ ] Repo social preview is set to `docs/images/social-preview.png` (Settings → General)
- [ ] Repo description and topics set (`macos`, `menu-bar`, `swift`, `system-monitor`)
- [ ] Download and first-launch path tested on a clean Mac
- [ ] Post HN on a weekday morning US Eastern; be around to reply for 2–3 hours
- [ ] Watch the animation once with sound on; the synthesized mix hasn't been listened to
- [ ] Stagger platforms rather than posting everywhere in the same hour
