# Embedding and exposing APIs

The Rust crate has no LeapTerm dependency. `PackageStore` accepts an application-owned root. Pass the listed activation `revision` to `invoke_at_revision`; re-enable, disable, upgrade, and grant changes produce a fresh revision. Keep any pending effects bound to that revision and the user's selected resource scope.

The Dart broker can expose an application API:

```dart
final registry = VibeHostRegistry();
registry.register(VibeHostApi(
  name: 'notes.append', version: 1,
  title: 'Append a note', description: 'Append text to the selected notebook',
  inputSchema: {
    'type':'object', 'properties':{'text':{'type':'string','maxLength':1000}},
    'required':['text'], 'additionalProperties':false,
  },
  outputSchema: {'type':'object','properties':{'saved':{'type':'boolean'}},'required':['saved']},
  readOnly: false,
  handler: (input, context) async {
    await context.check();
    // Validate the host-selected notebook and commit atomically with its
    // authorization. Never accept a guest's arbitrary filesystem path.
    await appendToSelectedNotebook(input['text'] as String);
    return {'saved':true};
  },
));
```

Send `registry.catalog` in `request.host.apis`. Use `registry.call(effect, grants, context, approve: ...)` with the real grant set and an `assertCurrent` callback that checks activation, user identity, and selected resource. Mutating calls require approval. The broker snapshots requests and schemas, checks API versions, bounds output, and rejects stale results. Hosts processing a whole batch may review the immutable batch once and pass its approval to the broker; do not swap or mutate requests after review.

Schema support is intentionally bounded: object/properties/required/additionalProperties, array/items/maxItems, string/minLength/maxLength, number/integer/minimum/maximum, boolean, null, and enum. Unsupported keywords fail registration. Input roots must be objects. Trusted handlers must enforce resource authorization as well as schema validation. They must recheck context immediately before side effects; an async timeout cannot undo an external write that already happened.

For UI mods, expose narrow hooks implemented by the host. LeapTerm's `leapterm.ui` v1 permits accent `emerald|blue|purple|amber`. It applies a temporary theme override, removes it on revocation, and never writes workspace preferences. The unchanged app is the default when no mod is enabled. This is the PoC equivalent of a Greasemonkey customization, expressed as a host-owned API instead of injected JavaScript.

Host APIs run in the application's trusted process. Plugin authors supply only Wasm plus declarative JSON; they cannot supply API handlers. Separate filesystem/network policy, persistence, permission UI, publisher trust, revocation, and multi-user tenant isolation remain host responsibilities. LeapTerm's implementation is the first integration example; this repository does not introduce a plugin marketplace or automatic updater.
