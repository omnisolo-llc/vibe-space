# VibeProtocol Host & Vibe Contract

VibeProtocol lets any host application opt in to user-vibed UI mods and temporary agent-generated views without exposing raw internals, arbitrary DOM/widget execution, or ambient network and storage access.

## 1. Opt-In Host Manifest & Capabilities

A host application explicitly declares:

- **Host identity**: `id` and human-readable `name`.
- **Offered capabilities**: each capability has a `name` (such as `telemetry.disk` or `likes.byFollower`), human `title`, declared `fields` map (`'public' | 'sealed'`), optional `sealedNote` and `sealedCannot`, a live `read()` function, optional `status()` health reporter, and synthetic `sample` rows.
- **Not offered (`notOffered`)**: plain-language list of actions the host never exposes to vibes (for example, running commands, reading secrets, or using the internet).

`host.manifest()` returns `{ protocol, host: { id, name }, capabilities, notOffered }` with `sample` data so an AI assistant can author vibes without ever seeing the user's live data.

## 2. Sealed Values ("Show Without Seeing")

Fields marked `'sealed'` are replaced before every vibe invocation with opaque random per-host handles (`VibeSealedHandle`):

```json
{ "sealed": "h_a1b2c3d4e5f60718" }
```

- **Deterministic per host**: the same real value maps to the same handle within a host, allowing vibes to group, sort, count, and match handles (such as tracking a bound server across refreshes) without learning the underlying string.
- **Draw-time resolution**: when a vibe returns a `VibeSealedHandle` in a view slot (`text`, `heading`, `badge`, `stat`, `bar` label/caption, or `table` cell), the host resolves the handle at draw time and renders it with a lock indicator and subtle dotted underline.
- **Fail-closed on forged handles**: if a vibe invents a handle that is not in the host's seal table, it resolves to `null` and renders empty text — never a real value and never the raw token.

## 3. Generated Permission Labels & Share Links

Before a vibe runs on live data, the host deterministically builds a three-part permission label from `vibe.needs` and the host manifest:

- **Reads**: one entry per capability in `vibe.needs` (`title`, plus `(<sealedNote>)` when applicable), or `Nothing from <host.name>` for portable vibes (`needs: []`).
- **Shows**: `Only inside its own box`.
- **Cannot**: capability `sealedCannot` strings, `host.notOffered`, and `Change anything in <host.name>`.

Key properties:

- **Compatibility checking**: `host.check(vibe)` rejects vibes whose `needs` include capabilities the host does not offer.
- **Permission stability & diffs**: updating an installed vibe without adding capabilities displays `"No new permissions."`; adding a new capability displays a permission diff and requires explicit approval (`Allow & save`).
- **Grant-free share links**: share payloads (`#vibe=...`) encode only the pure `VibeSpec` (`id`, `name`, `wish`, `version`, `needs`, `refresh`, `source`). They never carry host permission grants, custom titles, notes, or sealed handle tables; recipients always review the generated label on their own host.

## 4. Declarative Views & Read Ledger

Vibes return `{ state, view }` JSON payloads rather than executable UI code. The host validates depth/node bounds and renders:

- Layout & typography: `column`, `row`, `card`, `heading`, `text`, `badge`, `divider`
- Metrics & visuals: `stat`, `bar` (with optional `#RRGGBB` `swatch`, `caption`, and `max`), `sparkline` (finite numeric series), `table`, `progress`
- Controls: `button` / `action`, `input`, `checkbox`, `option_group`
- Semantic tones: `'default' | 'ok' | 'warn' | 'danger'`

Every run tracks a `VibeReadLedger` (`reads` count per capability, `sent`, `changed`, `calls`, `lastError`) and an `inspect()` snapshot showing the exact sealed `input` handed to the sandbox.

## 5. Host-Isolated Lifecycle Management

Installed vibes are stored per instance (`instanceId`) in `VibeInstalledRecord`:

- **Host-only metadata**: custom `title` and `note`, `pinned`, `paused`, `collapsed`, and display `order` live solely on the host record and **never** enter sandbox `input` or share links.
- **Multi-instance support**: the same vibe `id` can be pinned multiple times with different `args` (for example, watching two different servers).
- **Card management (`⋯` menu)**: `Edit…` (wish remixing or direct code editing with sandbox preview), `Rename`, `Inspect`, `Share…`, `Pause`/`Resume`, `Pin to top`/`Unpin`, `Move up`/`Move down`, `Revert`, and `Delete` with inline **Undo** (`restoreRecord`).
- **Version history**: edits to `source`, `version`, or `needs` push the prior snapshot onto `history` (up to 10 entries) for one-click revert. Persisted vibes are retained even if a capability is temporarily offline, revoked, or unavailable.

## 6. Source Health States & Graceful Degradation

Capability availability is modeled explicitly via `VibeSourceMode`:

| State | Meaning | Host Behavior |
| --- | --- | --- |
| `live` | Source is online and returning live rows | Normal refresh and live rendering |
| `sample` | User opted into synthetic sample preview | Uses `cap.sample` with a clear banner and `Return to live` action |
| `offline` | Source or transport temporarily disconnected | Preserves last good view in a stale/dimmed state (or shows calm unavailable notice if never rendered); keeps `lastError` clear |
| `revoked` | User or host turned off access to a capability | Preserves last good view / explains why access is off; offers `Retry`, `Preview sample`, and `Edit` |
| `missing` | Capability is not offered by this host | Preserves record metadata without crashing; explains what is missing |

Hosts call `notifySourceChange()` whenever source availability or bound entities change so active vibe runs re-evaluate and recover automatically as soon as the source returns.

## 7. Dedicated Vibe Space Panel & Temporary Agent Embeds

Hosts expose VibeProtocol in two places:

- **`VibeSpacePanel`**: dedicated panel for inspecting what the host offers, authoring vibes from wishes, previewing on sample data, reviewing permission labels, managing installed cards (`⋯` menu), importing shared links, and browsing portable vibes (`needs: []`).
- **`VibeEmbedCard`**: compact inline box inside an AI agent's reply, marked `Temporary`, displaying a live view, a `Reads:` summary line, an `Inspect` toggle, and a **Pin to Vibe Space** flow (pre-filled editable title & note + permission label).

## 8. Conditional View Triggers (`when`) & Presets

VibeProtocol includes a declarative trigger condition engine (`VibeTriggerCondition` / `when`) so both built-in host presets and user/agent-authored Vibe views can appear automatically when matching terminal, window, or host conditions occur.

### `when` Schema & Matchers

`when` may be declared on `VibeSpec`, `VibeInstalledRecord`, `VibeCanvasPayload`, `VibeConditionalEntry`, and extension `Manifest` / `Contribution` records:

```json
{
  "program": ["agy", "claude"],
  "cwd": "*/example-project*",
  "context": {
    "inTmux": true,
    "ports": "3000"
  },
  "not": {
    "windowTitle": "*production*"
  }
}
```

- **Target fields**:
  - `program` / `command`: foreground executable name (matching full path or basename) and full command/argv string.
  - `window` / `surface` / `windowTitle`: active UI surface (such as `"terminal"`), tab/pane identifier, or OSC/tmux window title.
  - `cwd` / `pathPattern`: normalized working directory matched via glob, regex, or exact path.
  - `env` / `context`: arbitrary host key/value predicates (`inTmux == true`, `gitRepo == true`, `portOpen == "3000"`, or list membership on `ports: ["3000", "5173"]`).
- **Boolean combinators**: `all` (AND), `any` (OR), `not` (NOT), and `always` (`true | false`), bounded to depth 16 and 64 items per branch.
- **Value matchers**: scalar shorthands (`"agy"`, `"docker*"`, `true`, `3000`, `["agy", "nvim"]`) or explicit operator maps (`exact`, `glob`, `regex`, `contains`, `prefix`, `suffix`, `exists`, `oneOf`, `caseSensitive`).

### Evaluation, Hysteresis & Reactive Decks

- **`VibeTriggerContext` & `VibeTriggerEvaluator`**: evaluates live host snapshots against `VibeConditionalEntry` items, reporting `activeEntries`, `newlyTriggeredIds`, `deactivatedIds`, and `heldIds` with configurable `holdMs` hysteresis and per-episode user dismissal (`dismiss(id)` resets automatically once the condition turns false).
- **`VibeConditionalRegistry` & Presets**: unifies built-in adaptive presets (`isPreset: true`, `registerPresets(...)`, `hydratePresetPayloads(...)`) with user-authored custom Vibe views (`vibe_ui`, `markdown`, `html`, `wasm`, or JS `VibeSpec`), preserving user enablement, pin, and custom `when` overrides across live refreshes and storage reloads.
- **`VibeConditionalController` & `VibeTriggeredViewDeck`**: reactive `vibe_space_flutter` widgets rendering active conditional Vibe cards inside `RepaintBoundary` containers with `tabularFigures` typography and `{{variable}}` context template hydration.

## 9. WeChat Mini Program Dual-Layer + Skyline Native Render Engine

VibeProtocol pairs an air-gapped logic runtime (**Layer 1 — `AppService`**) with a native Flutter/Skia view engine (**Layer 2 — `Skyline`**) so custom and AI-generated Vibes run at 60/120 fps with zero WebViews, zero iframes, and zero DOM/network access by default:

- **Layer 1 (`AppService` Logic Sandbox)**:
  - Authored via `defineMiniProgram({ data, template, onLoad, onShow, onHide, onDataUpdate, methods })` (or `wasm32` `vibe_alloc` / `vibe_invoke` modules).
  - Air-gapped execution: `window`, `document`, `fetch`, `XMLHttpRequest`, `WebSocket`, `RTCPeerConnection`, `localStorage`, `navigator`, `eval`, and `Function` are statically and dynamically absent.
  - Incremental state bridge: `this.setData({ 'meta.tps': 94.2, 'bars[0]': 61 })` patches nested object/array paths with prototype-pollution guards, a **`<= 64 KiB`** per-diff cap, and a **`<= 30/s`** rate limit.
- **Layer 2 (`Skyline` VXML Template + Native `canvas` 2D)**:
  - `compileVibeTemplate(template, scope)` evaluates `if` / `v-if` / `wx:if`, `for` / `v-for` / `wx:for` (`forItem` / `forIndex`), `{{path}}` typed bindings (preserving `{ "sealed": "h_..." }` handles, arrays, numbers, and booleans), scoped `WXSS` `style` tokens, and `bindtap` / `bindinput` + `dataset` (`data-*`) event round-trips back to Layer 1 `methods[handler](event)`.
  - First-class `canvas` primitive (`{ "type": "canvas", "width": 260, "height": 56, "commands": [...] }`) renders bounded 2D vector draw-lists (`clear`, `rect`, `rrect`, `circle`, `arc`, `line`, `path`, `polygon`, `bars`, `text`, `linearGradient`) directly onto Flutter's `CustomPaint` Skia/Impeller canvas (and `<svg>` / terminal sparklines on web/CLI), strictly capped at **`<= 2,000`** draw commands per frame tree.
