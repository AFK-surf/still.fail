# Working on the rules (for agents)

- The workspace lock's, a person's and the vault's rules (which entries and versions may follow, who may do what, the
  forms that are hashed and signed) are written once here in MoonBit (`src/`), with what is proved of them
  (`*.mbtp`, `moon prove`, CI's `rules.yml`). `build.sh` builds them to `js/rules.js`, which the station
  (`station/src/cloud/lock.ts`, `station/src/vault/crypto.ts`), the cloud (through the station's lock) and the core
  take as it is. It is committed: a change to `src/` runs `build.sh` and commits what it made; never edit it by hand.
- It runs in Node, in a Cloudflare Worker (no random values before a request: `build.sh` defers the hash seed) and in
  Hermes (`hermes-check.sh`). `protocol/` models the lock's and a person's protocols for Tamarin
  (`protocol/check.sh`); a change to what they sign changes the model too.
