# Working on the rules (for agents)

- The workspace lock's, a person's and the vault's rules (which entries and versions may follow, who may do what, the
  forms that are hashed and signed) are written once here in MoonBit (`src/`), with what is proved of them
  (`*.mbtp`, `moon prove`, CI's `rules.yml`). `build.sh` builds them to `js/rules.js`, which the station
  (`station/src/cloud/lock.ts`, `station/src/vault/crypto.ts`), the cloud (through the station's lock) and the core
  take as it is. It is committed: a change to `src/` runs `build.sh` and commits what it made; never edit it by hand.
- It runs in Node, in a Cloudflare Worker (no random values before a request: `build.sh` defers the hash seed) and in
  Hermes (`hermes-check.sh`). `protocol/` models the lock's and a person's protocols for Tamarin
  (`protocol/check.sh`); a change to what they sign changes the model too.
- `src/lock/chain.mbt` (a log's active chain by the fork choice of `src/fork`), `src/lock/roster.mbt` (a workspace's
  list from its people's own logs) and `fold_person_ws` are the rules the lock's next sync is built to (the root
  AGENTS.md, 2026-11-12): the station and the core go by `lock_chain_js` and `person_chain_js`
  (`station/src/cloud/log-keep.ts`, `client/core-ts/src/lock-keep.ts`, leaving out the `ws.*` kinds), nothing calls the
  rest yet, and `fold_person` refuses the `ws.*` kinds until every
  station takes them. They are held to the models they were written from (`station/test/lock-fork-choice-model.ts`,
  `station/test/lock-roster-model.ts`) by `station/test/rules-fork.test.ts`: a change to either changes both.
  `roster.mbt` and `fold_person_ws` take a workspace's statements in the clear, which the stations of a person's
  other workspaces would read; the model's fourth round (`station/test/lock-roster4-model.ts`, 2026-11-13) says what
  they are to become before anything calls them: a statement a commitment in the log (`ws {t, h}`) with its body kept
  by its workspace alone, bodies in the order their signer held them (`prev`), removals naming bodies not entries,
  web devices in their person's log held to the keeper's clock, the settings and `off` the root's, `off` a state.
