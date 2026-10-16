# Protocol v1

A package is JSON with `manifest` (the exact UTF-8 string signed by Ed25519), `signature` (base64, 64 bytes), and `module` (base64 Wasm). A separately trusted publisher key is 32 raw Ed25519 public bytes encoded as base64. The manifest contains `id`, increasing integer `version`, `api_version: 1`, `name`, `license`, `module_sha256` (base64 SHA-256), `capabilities`, `network_origins`, and `contributions`. Examples contain complete manifests except the hash, which `pack` computes. Upgrades clear grants and disable the package. Publisher substitution and downgrade are rejected.

The first ABI retains `omni_` export names for compatibility with LeapTerm packages:

```c
// The module also exports its linear memory as "memory".
uint32_t omni_alloc(uint32_t length);
uint64_t omni_invoke(uint32_t pointer, uint32_t length);
// Return: (uint64_t(output_length) << 32) | output_pointer
```

A fresh instance handles each invocation. The host writes JSON into the guest allocation. Guest output is a JSON object, at most 1 MiB. Preserve transient state in `result.state`; it comes back in the next invocation. The guest never owns an application object or native pointer.

```json
{"api_version":1,"command":"open","arguments":{},"state":null,"results":[],"host":{"framework_version":"0.2.0","apis":[]}}
```

The trusted host advertises exposed APIs in `host.apis`: name, version, capability, read_only, input_schema, and output_schema. Each API has an independent `api:<name>` grant. A guest can discover available APIs but cannot register its own host implementation.

```json
{"effects":[{"id":"appearance","method":"host.call","capability":"api:leapterm.ui","arguments":{"api":"leapterm.ui","version":1,"input":{"accent":"purple"}}}]}
```

The host freezes the original effects, validates grants and schema, reviews mutations, rechecks activation and session context, then executes those same requests. It never reruns guest code with a `confirmed_effects` flag. New requests in later rounds require their own review. Completion arrives as `command: "host.results"` and `results: [{"id":"appearance","value":{"applied":true}}]`.

Compatibility host methods are `network.fetch`, `terminal.read`, and `terminal.write`, granted independently as `network`, `terminal_read`, and `terminal_write`. These are also explicit host APIs, never ambient access. HTTPS fetches require exact signed origins and host transport checks. Opaque credential IDs do not give the guest access to a vault or inject credentials in this PoC.

Views support text, heading, badge, input, action, row, column, card, divider, and progress. The host owns rendering, layout, and callbacks. Limits are depth 16, 1,024 nodes, 100 children per container, 64k text characters, and unique input IDs. No HTML or arbitrary widget code executes. `sdk/typescript/index.d.ts` is the maintained public contract.

Slot names describe placements a host may implement. The first LeapTerm example uses `quick_command`. Declaring another slot does not create a new host placement; inspect host documentation before using it.
