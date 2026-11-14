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
