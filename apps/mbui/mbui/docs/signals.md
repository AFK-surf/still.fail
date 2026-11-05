# Signals

`src/signals` is alien-signals 3.2.1 (https://github.com/stackblitz/alien-signals), ported line for line:
`system.mbt` is its `src/system.ts` (the graph: what reads what, a change pushed down as pending and pulled back up as
what is read checks what it read), `signals.mbt` its `src/index.ts`. A change to either starts from alien-signals'
own source, not from what the port seems to want.

- `signal(v)` with `get` and `set`; `computed(getter)` with `get` (the getter is given what it made last); `effect`,
  `effect_cleanup` (its run returns its cleanup), `effect_scope`, `trigger`, `start_batch` / `end_batch`,
  `active_sub` / `set_active_sub`, as alien-signals has them.
- The same value is `same`: `physical_equal` without one, which is JS's `!==` for numbers and for objects. Strings and
  other values compared by what they hold say `same=fn(a, b) { a == b }`.
- Nothing throws: there is no `finally` to put the graph back after a getter or an effect that throws.
- Added for what keeps computeds of its own (still.fail's sfbase `Kept`, `Derived`): `Computed::peek` (what it made
  last, not worked out again), `Computed::dispose` (it lets go of what it read, as alien-signals' `unwatched` does
  with a computed nothing reads any more: under reference counting a computed left linked to a signal would never be
  let go), `Signal::watched`, `Computed::watched` (a part kept as it was drawn, `Ctx::kept_part`, follows what its
  build read: what follows a computed keeps it), `untracked`.
- Added for a computed that holds what is built for it after it ran (a part kept holds its list's rows, laid out
  after the part's build): `Computed::reading` (what a function reads, read by the computed as well, as though its
  run read it last) and `Computed::lend` (what one computed read, read by another as well). Let go as the computed's
  run reads anew, as what it read is.

## Under reference counting

What index.ts makes as small objects a garbage collector takes back for next to nothing is, under MoonBit's
reference counting, a malloc, a free and a count kept on every reference to it; and a reference bound to a name and
passed on is counted too. So the port makes once what index.ts makes often, and looks at fields in place where it
can, the algorithm unchanged:

- A signal and a computed are their node (`struct Signal[T](ReactiveNode)`): what index.ts's node of that kind holds
  besides the graph's fields (a signal's values, a computed's getter and value, an effect's fn) is the node's `own`,
  its type left out and said back by what knows it (`coerce`), and how it brings itself up to date is one function a
  type of value (`signal_update`, `computed_update`), not a closure a node: two objects a signal, where a handle, a
  state, a closure and the node's kind made five.
- checkDirty's and propagate's stacks are arrays kept from call to call (`check_frames`, `propagate_frames`), not a
  frame object a level.
- A read makes link's two first checks itself (`track`), on the fields as they are: what is bound to a name and passed
  on is counted, and nearly every read is one of those two cases (what was read just before, or what was read next
  last time).

A change ported from alien-signals keeps to that: nothing made again on every read, write or update that is made once
now, nothing bound and passed on that can be looked at where it is. (A computed of a value MoonBit keeps boxed in an
Option, a Double, still boxes it every time it changes: the getter is given what it made last as `T?`. Int, Bool and
references are not boxed.) `bench/signals` measures it against alien-signals and the other JS engines, and replays
what still.fail's app itself does with the signals (its README).

## Tests

`effect_wbtest.mbt` is alien-signals' own tests; `conformance_*_wbtest.mbt` the cases of the conformance suite it
runs (reactive-framework-test-suite 0.0.2) about signals, computeds, batches and untracked reads, each case as it is
there. Run them with `moon test --target native -p mbui/signals`.
