# Signals

`src/signals` is alien-signals 3.2.1 (https://github.com/stackblitz/alien-signals), ported line for line:
`system.mbt` is its `src/system.ts` (the graph: what reads what, a change pushed down as pending and pulled back up as
what is read checks what it read), `signals.mbt` its `src/index.ts`. A change to either starts from alien-signals'
own source, not from what the port seems to want.

- `signal(v)` with `get` and `set`; `computed(getter)` with `get` (the getter is given what it made last); `effect`,
  `effect_cleanup` (its run returns its cleanup), `effect_scope`, `trigger`, `start_batch` / `end_batch`,
  `active_sub` / `set_active_sub`, as alien-signals has them.
- The same value is `same`: `physical_equal` by default, which is JS's `!==` for numbers and for objects. Strings and
  other values compared by what they hold say `same=fn(a, b) { a == b }`.
- Nothing throws: there is no `finally` to put the graph back after a getter or an effect that throws.
- Added for what keeps computeds of its own (still.fail's sfbase `Kept`, `Derived`): `Computed::peek` (what it made
  last, not worked out again), `Computed::dispose` (it lets go of what it read, as alien-signals' `unwatched` does
  with a computed nothing reads any more: under reference counting a computed left linked to a signal would never be
  let go), `Signal::watched`, `Computed::watched` (a part kept as it was drawn, `Ctx::kept_part`, follows what its
  build read: what follows a computed keeps it), `untracked`.

## Tests

`effect_wbtest.mbt` is alien-signals' own tests; `conformance_*_wbtest.mbt` the cases of the conformance suite it
runs (reactive-framework-test-suite 0.0.2) about signals, computeds, batches and untracked reads, each case as it is
there. Run them with `moon test --target native -p mbui/signals`.
