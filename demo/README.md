# VibeProtocol Browser Demo

A clickable, zero-dependency browser demo of **VibeProtocol**: an open protocol that lets any app that opts in be safely extended by its own users.

A user writes a wish in plain language. Their AI creates a small, sandboxed program called a **vibe** against the host app's declared capabilities and synthetic sample data. The host shows a plain-language permission label (**Reads**, **Shows**, **Cannot**), executes the vibe in an isolated sandbox, and renders the resulting UI inside its own box while keeping sealed fields (such as server hostnames or follower names) hidden behind opaque random handles.

Two completely unrelated host apps run on the exact same shared kit (`kit/vibekit.js`, `kit/vibespace.js`, `kit/vibespace.css`):
- **LeapTerm (demo host)** — a dark operations & server telemetry tool (`apps/leapterm/index.html`)
- **Moments (demo host)** — a light photo-sharing feed (`apps/moments/index.html`)

## How to Run

No build step, `npm install`, or external network access is needed.

### Option 1: Local HTTP server

```bash
cd core/framework/demo
python3 -m http.server 8765
```

Then open <http://localhost:8765/> in a modern browser.

### Option 2: Directly from disk (`file://`)

Open `core/framework/demo/index.html` (or either app's `index.html`) directly in your browser. All scripts are classic `<script src>` tags with no ES module imports or external assets.

## What Is Real, Scripted, and a Stand-In

| Category | Component | Details in this demo |
| --- | --- | --- |
| **Real** | Sandbox boundary | Vibe code runs only in a Web `Worker` created inside a hidden `<iframe sandbox="allow-scripts">` with a restrictive `Content-Security-Policy` (`default-src 'none'`, no network, no storage/cookies, no parent DOM); if the `Worker` cannot start, the kit fails closed and refuses to run the vibe. `'unsafe-eval'` is allowed only inside that sandboxed frame so the `Worker` can compile the vibe; the host page never evaluates vibe source. Calls have a `1000 ms` timeout and a `64 kB` output cap. |
| **Real** | Host-drawn UI | Vibes only return declarative JSON view trees (`column`, `row`, `card`, `heading`, `text`, `badge`, `stat`, `bar`, `sparkline`, `table`, `divider`, `button`). The host kit builds and patches the DOM using `textContent` (never `innerHTML`) and styles it with the host's `--vs-*` theme tokens. |
| **Real** | Capability checks | Hosts declare offered capabilities and fields; `host.check(vibe)` blocks vibes whose `needs` are not offered by the current host (for example, a LeapTerm disk vibe cannot run in Moments), and `host.sourceStatus(vibe)` checks live availability. |
| **Real** | Graceful unavailability & recovery | When a declared capability goes offline, is revoked, or `read()` fails, mounted runs preserve their last good view (`.vk-view-stale`) or show a calm `div.vk-unavailable` state, let users retry or preview synthetic sample data (`run.setDataMode`), and heal automatically via `host.notifySourceChange()` when the source returns. |
| **Real** | Vibe lifecycle management | Installed vibes are stored per instance (`instanceId`) in `localStorage` (`vibekit:<host id>`) with host-only custom titles and notes (never sent into the sandbox or share links), version history with one-click revert, pause/resume, collapse, pin-to-top/reordering, filtering, and delete with undo. |
| **Real** | Sealed values | Fields marked `'sealed'` are deep-copied and replaced with random `crypto.getRandomValues` handles (`{ sealed: 'h_...' }`) stored per host in `localStorage` (`vibekit:<host id>:handles`). The vibe can sort, group, and compare handles, while the host resolves them back to `span.vk-sealed` only at draw time; unknown handles render as nothing. |
| **Real** | Generated label | `host.label(vibe)` deterministically generates the **Reads**, **Shows**, and **Cannot** rows directly from the vibe's `needs` and the host's capability manifest. |
| **Real** | Read ledger | Every invocation increments per-capability read counters (`run.ledger()`), records `lastError`, and exposes the exact serialized `input` and `output` in `run.inspect()`. |
| **Real** | Share links | `VibeKit.share.encode` / `decode` serialize the vibe package (capped at 32 kB) into a `#vibe=...` URL fragment without carrying permission grants; recipients see the label and decide on their own host. |
| **Real** | Two hosts on one kit | Both **LeapTerm** and **Moments** share the exact same `VibeKit` and `VibeSpace` implementation, including portable vibes (`needs: []`) such as the Focus timer. |
| **Scripted** | The AI | Wish chips trigger a 3-step authoring playback using pre-written vibe packages rather than calling a live LLM. |
| **Scripted** | Apps' data | Server telemetry in LeapTerm and posts/followers in Moments are synthetic in-memory datasets that drift periodically to look alive. |
| **Scripted** | Agent's replies | The LeapTerm agent suggestion chip plays a scripted reply and embeds a live `CPU and memory` vibe view. |
| **Stand-in** | Browser sandbox for Wasm | `<iframe sandbox="allow-scripts">` + Web `Worker` stands in for the real framework's Wasm runtime. |
| **Stand-in** | Demo JS kit for Rust & Dart | `kit/vibekit.js` and `kit/vibespace.js` are self-contained browser JavaScript rather than the framework's Rust and Dart implementation. |
| **Stand-in** | Per-call data handoff | Sealed capability rows are fetched by the host and passed in `input.data` on each call instead of using the real protocol's asynchronous request/reply round trip. |

## Features Demonstrated

- **Vibe Space lifecycle management**: Customize a vibe's host-only title and note when adding or renaming; edit any installed vibe either by wish remixing or in the live JS code editor with sandbox testing; inspect version history and revert in one click; pause/resume, collapse/expand, pin to top, reorder, filter, and delete with undo.
- **Graceful data-source unavailability & recovery**: Toggle LeapTerm's telemetry feed or individual servers offline, or revoke follower likes access in Moments. Bound cards preserve their last known reading (`.vk-view-stale`) or display a calm `div.vk-unavailable` explanation with **Retry** and **Preview sample** actions while portable vibes (such as the Focus timer) keep running uninterrupted, and recover automatically once the source comes back.

## Directory Layout

- `index.html` — Demo start page with tour and links to both host apps.
- `kit/vibekit.js` — Core `window.VibeKit` host, sandbox runner, handle sealing, share codec, and Contract V DOM renderer/patcher.
- `kit/vibespace.js`, `kit/vibespace.css` — Shared `window.VibeSpace` UI (`mountPanel`, `embed`, `showOffer`) and `.vk-*` themeable styles.
- `vibes/focus-timer.js` — Portable 25-minute Focus timer (`needs: []`) in `window.VIBE_GALLERY`.
- `apps/leapterm/` — LeapTerm (dark operations host app, `?as=teammate` support, `disk-watch` v1/v2 and `server-load`).
- `apps/moments/` — Moments (light photo-sharing host app, `top-posts` and `top-fans`).
- `checks/` — Automated Playwright verification scripts (`hostile.mjs`, `story.mjs`).
