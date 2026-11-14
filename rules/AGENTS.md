# Working on the rules (for agents)

- The workspace lock's, a person's and the vault's rules (which entries and versions may follow, who may do what, the
  forms that are hashed and signed) are written once here in MoonBit (`src/`), with what is proved of them
  (`*.mbtp`, `moon prove`, CI's `rules.yml`). `build.sh` builds them to `js/rules.js`, which the station
  (`station/src/cloud/lock.ts`, `station/src/vault/crypto.ts`), the cloud (through the station's lock) and the core
  take as it is. It is committed: a change to `src/` runs `build.sh` and commits what it made; never edit it by hand.
- It runs in Node, in a Cloudflare Worker (no random values before a request: `build.sh` defers the hash seed) and in
  Hermes (`hermes-check.sh`). `protocol/` models the lock's and a person's protocols for Tamarin
  (`protocol/check.sh`); a change to what they sign changes the model too.
- `src/lock/chain.mbt` (a log's active chain by the fork choice of `src/fork`), `src/lock/body.mbt`,
  `src/lock/roster.mbt` and `src/lock/state4.mbt` (a workspace said in its people's own logs: commitments `ws {t, h}`
  there, their bodies kept by the workspace alone, the list and one `LockState` from the bodies in force) are the
  rules the lock's next sync is built to (the root AGENTS.md, 2026-11-12), written from the model's fourth round
  (`station/test/lock-roster4-model.ts`, its defaults; 2026-11-13). The station and the core go by `lock_chain_js` and
  `person_chain_js` (`station/src/cloud/log-keep.ts`, `client/core-ts/src/lock-keep.ts`); `fold_person` takes `web`,
  `web.remove` and `ws` and the workspace chain `moved {root}` from this build on, which every part takes as it is:
  an older station or app refuses a chain with a kind it does not know, so a device writes them only once everything
  that keeps or reads that log or workspace runs a build that takes them (client/core-ts/AGENTS.md, A lock held here;
  the user, 2026-11-14: 无感迁移, no date, no switch, nobody told to update). They are
  held to the models they were written from (`station/test/lock-fork-choice-model.ts`,
  `station/test/lock-roster4-model.ts`) by `station/test/rules-fork.test.ts`: a change to either changes both.
- A device of a person's log has two keys there: its `key`, sealed for its person's presence, which signs that log
  alone, and the `sign_key` its entries say, the key it signs a workspace's things with unasked (a vault's versions,
  items and box certificates). `fold_person` keeps the last `sign_key` said and every one said; `state4` names an app
  device by it, never by its `key` (the lead, 2026-11-13: nothing the workspace signer signed checked out against a
  moved state). One whose log says none is listed and signs nothing of the workspace's, but by the signer the chain as
  it moved names it with (below).
- Once a chain moved, the station and the core read it with `state4_moved` and `roster_moved`, as it moved beside the
  logs (the model's D6, the lead's, 2026-11-14): what the logs have not said yet of someone it named, it still says
  (`roster.mbt` `Carried`, `state4.mbt` `carry_of`), so `moved` alone hands it over, nobody waited for or asked. A
  removal takes back the chain's saying of its subject whether it names it or not, so one said under build 9040's
  rules (the logs alone) still takes out whom it did; someone re-admitted to the log the chain bound them to (or bound
  by an admit where the chain bound them to none) has what the chain carried of theirs again (the lead, 2026-11-14:
  re-admitting is an owner's or admin's own act). Every reader must make the same state, so the build that reads them
  is a move's floor (`MOVED_FROM_BUILD`, station/src/api/moved-from.ts) and a station says `carried` in its `serves`.
- A member the chain bound to no log binds a log of their own to themselves (the lead, 2026-11-14): `bind {key, sig}`
  in that log, `sig` the signer's (`key`, one the chain names for an own, signing app device of theirs) over
  `bind_form` (the workspace, the member, the log, the `moved` entry's hash) under `bind_tag`, a tag no other form a
  device's signer signs has (`Crypto.tagged_sig_valid`: the tag, a NUL, the form's SHA-256; a lock entry's is
  `stillfail-lock/1 sig`, a vault's `stillfail-vault*/1`, a rig's `stillfail-rig-*/1`). It sets the chain's own admit
  of them to that log (`roster.mbt` `binds_of`), so nothing new is labelled: a removal of them takes it back, a real
  admit of their role binds before it. A station says `bind` in its `serves`.
- Two bindings of one member (the lead's review, 2026-11-14) settle by what their signer cannot choose, never by an
  entry hash (ground at will by whoever makes the log): a binding whose log took off a device that proves another
  attacks it, the grounded extension decides as the list does for removals, and of those in, the smaller signer key
  wins (then the smaller entry hash). Every device a binding not out took off, the chain carries no more: so a device
  the member took off never binds them again (a thief's log bound by a lost phone would else seal their vaults to the
  thief), as a removal the stations took was final before the move. Where each took the other's device off, nobody
  is in: the member stands bound to no log, without any of those devices, until an owner or admin admits them (a real
  admit binds before any `bind`), the manual case the owner took for two devices removing each other. Known and
  taken: a removed signer whose log reaches a reader (by a station or the cloud, the lock's adversary) can so put the
  member back to unbound with those devices out until then; proofs by several of the member's signers outweighing one
  is not built.
- After a move the root's person is a member like any other (the lead, 2026-11-14; the owner's: a moved workspace does
  for every person what an unmoved one does): the root's log is what the workspace is rooted in and what its pair
  says always counts, as an owner's, but that its person is in the list, bound by it, is an implicit admit (`~root`,
  `roster.mbt` `root_admit`; the model's D7, `rootOut`), which an owner's `member.remove` of them cancels only where
  its `cancels` names the root's genesis hash (a removal of them from before this rule named nothing that counts, and
  still does nothing for every reader). While it is in it binds them before any other admit of theirs; once it is out
  their real admits bind them as anyone's (none in: not in the list), and nothing of the chain as it moved is carried
  of theirs. Known and taken: a device of the root's log, its person taken out, still says statements that count if
  they reach a reader (as before, when its person could not be taken out at all), and the root's word against an
  owner's is the root's, so the root's person with a device in hand is never locked out by an owner for good. A reader
  from before reads such a removal as nothing: a core says one only where every station the list names says
  `rootout` in its `serves`.
