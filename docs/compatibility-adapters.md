# Multi-Language & Universal UI Compatibility Adapters

Vibe Space separates **what a vibe computes** from **how a host draws it**. Vibes execute in a sandbox and return declarative JSON (`{ state, view }`) with opaque `{ "sealed": "h_..." }` handles; compatibility adapters allow any guest language, any UI dialect, and any host toolkit to interoperate without relaxing isolation.

## 1. Multi-Language Guest & Host Support

### Guest languages (`wasm32` ABI + JS/JSON)
- **Vendor-neutral Wasm exports**: Hosts accept `vibe_alloc` and `vibe_invoke` as primary exports alongside `omni_`, `leap_`, and `leapterm_` aliases (`runtime/src/lib.rs`, `web/worker.js`).
- **SDK helpers**:
  - Rust (`sdk/rust`) and C (`sdk/c/vibe_space.h`) export `vibe_alloc` / `vibe_invoke` cleanly, and any import-free `wasm32` toolchain (C++, TinyGo, Zig, AssemblyScript) can target the same 2-function ABI.
  - JavaScript `invoke(input)` functions and declarative JSON specs run in browser sandboxes (`demo/kit/vibekit.js`) and Dart (`dart/lib/src/vibe_protocol.dart`).

### Host SDKs
- **Rust**: `vibe-space-runtime` (`runtime/src/adapter.rs`)
- **TypeScript / JavaScript**: `@vibe-space/sdk` (`sdk/typescript/adapters.mjs`, `demo/kit/vibekit.js`)
- **Dart / Flutter**: `package:vibe_space` (`dart/lib/src/compatibility_adapter.dart`) and `package:vibe_space_flutter` (`flutter/lib/src/vibe_widget_adapter.dart`)

## 2. Inbound UI Dialect Adapters (A2UI, Adaptive Cards, Markdown)

Agents and external tools speaking other declarative UI formats convert directly into validated canonical `VibeView` trees before rendering:

- **TypeScript / JS**: `adaptExternalUi(raw)` (`VibeKit.adaptUi`)
- **Dart**: `VibeUiCompatibilityAdapter.adapt(raw)`
- **Rust**: `adapter::adapt_external_ui(&value)`

Supported inbound formats:
- **A2UI**: both `surfaceUpdate.components` adjacency lists (with cycle detection) and nested component objects (`Text`, `Heading`, `Badge`, `Button`, `Card`, `Row`, `Column`, `TextField`, `CheckBox`, `MultipleChoice`, `ProgressBar`/`LinearProgress`, `Metric`/`Stat`, `Table`, `Divider`, `Bar`, `Sparkline`).
- **Adaptive Cards**: `type: "AdaptiveCard"` with `TextBlock`, `Container`, `ColumnSet`/`Column`, `FactSet`, `Table`, `Input.Text`, `Input.Toggle`, `Input.ChoiceSet`, `ActionSet`, `Action.Submit`/`Action.Execute`, and `ProgressBar`.
- **Markdown**: headings, lists, dividers, tables, and paragraphs.

All inbound adapters preserve `{ "sealed": "h_..." }` handle objects, enforce depth and node limits, and strip unsafe attributes or script payloads.

## 3. Outbound UI Render Adapters

Once normalized to canonical `VibeView`, hosts can render into any UI framework:

| Target Toolkit | Adapter API | Notes |
| --- | --- | --- |
| **React, Preact, Vue 3, Solid, SSR** | `renderWithH(h, view, opts)` | Zero `document` dependency; emits `vk-sealed` spans and `onCommand`/`onInput` callbacks |
| **Angular, Svelte, Lit, HTMX, Plain HTML** | `defineVibeWebComponents(env)` | Registers `<vibe-view>`, `<vibe-embed>`, and `<vibe-space>` Custom Elements |
| **Flutter Material / Cupertino / Custom** | `VibeWidgetAdapter.material()`, `.cupertino()`, `.custom(...)` | Swaps widget families or individual node builders while enforcing protocol validation & sealed handle rules |
| **SwiftUI, Jetpack Compose, Qt, GTK, WinUI, React Native** | `resolveViewTree` / `resolve_view_tree` / `resolveVibeViewTree` | Outputs a headless handle-resolved JSON IR (`sealedResolved` boolean; forged handles render empty `""`) |
| **Terminal / CLI / SSH TUI** | `renderToTerminal` / `render_terminal` / `VibeTerminalRenderer.render` | Renders Unicode bars (`█░`), sparklines (`▁▂▃▄▅▆▇█`), tables, optional ANSI tones, and `🔒` sealed prefix |
| **Markdown & Escaped HTML SSR** | `renderToMarkdown`, `renderToHtmlString` | Safe plain-Markdown and strictly HTML-escaped string outputs |

## 4. Human Languages, Unicode & RTL (`i18n`)

- **Built-in locale packs**: `en`, `zh`, `ja`, `ko`, `es`, `fr`, `de`, and `ar` (`rtl: true`), accessed via `getVibeStrings(locale, overrides)` (TS/JS), `VibeStrings.forLocale(locale)` (Dart), and `locale_strings(locale)` (Rust), with regional subtag fallback (e.g. `ar-SA` -> `ar`, `zh-CN` -> `zh`).
- **RTL & bidi layout**: hosts and widgets apply `dir="rtl"` / `Directionality(textDirection: TextDirection.rtl)` when an RTL locale is active and `dir="auto"` on user-supplied titles, notes, and captions.
- **Full UTF-8 safety**: `#vibe=...` share tokens (`TextEncoder`/`TextDecoder`), host-only titles/notes, and sealed values preserve CJK, Arabic, accented scripts, and emoji without corruption.
