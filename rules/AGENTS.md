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
  `web.remove` and `ws` and the workspace chain `moved {root}` from this build on, which every part takes as it is,
  while nothing signs them and nothing calls the rest yet: an older station or app refuses a chain with a kind it does
  not know, so nothing writes them until this build has been out seven days (the root AGENTS.md, Changes). They are
  held to the models they were written from (`station/test/lock-fork-choice-model.ts`,
  `station/test/lock-roster4-model.ts`) by `station/test/rules-fork.test.ts`: a change to either changes both.
