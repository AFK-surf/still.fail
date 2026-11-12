// The rules' JS run in Hermes, as the core is (bundled by esbuild into one script): the vector's text as Node gets it.
import { canonical_of, entry_text_of, lower_role, person_chain_js, roster_js, tie_of_js } from "./js/rules.js";
const vector = { v: 1, ws: "01HZZZZZZZZZZZZZZZZZZZZZZZ", seq: 3, prev: "ab".repeat(32), at: 1700000000, kind: "device", body: { sub: "s", id: "cd".repeat(32), kind: "web", label: "Chrome · 名字 😀 \u0000", exp: 1702592000 } };
print(entry_text_of(vector));
print(canonical_of(JSON.parse('{"b":[1,2,{"z":null,"a":"\\ud800x"}],"a":1.5}')));
print(canonical_of(JSON.parse('{"b":[1,2,{"z":null,"a":"\\ud800x"}],"a":-9007199254740991}')));
print(lower_role("owner", "member"));
// A person log that branches, its active chain and the workspace's list from it (src/lock/chain.mbt, roster.mbt), with a
// stand-in for the cryptography (Hermes has none of node's): only what Hermes and Node print of the same is compared.
const fnv = (s, seed) => { let h = seed >>> 0; for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619) >>> 0; return h.toString(16).padStart(8, "0"); };
const crypto = { sha256Hex: (s) => [1, 2, 3, 4, 5, 6, 7, 8].map((k) => fnv(s, 2166136261 + k)).join(""), sigValid: () => true, validKeyId: () => true, endpointProof: () => false };
const hash = (e) => crypto.sha256Hex(entry_text_of(e));
const key = "ed25519:" + "aa".repeat(32), sig = { key, alg: "Ed25519", sig: "00" };
const g = { v: 1, ws: "person:alice", seq: 0, prev: null, at: 1, kind: "genesis", body: { sub: "alice", device: { key, id: "bb".repeat(32), label: "app" } }, sig };
const gh = hash(g);
const admit = { v: 1, ws: "person:alice", seq: 1, prev: gh, at: 2, kind: "ws.member", body: { ws: "W", sub: "bob", lock: "cc".repeat(32), role: "admin" }, sig };
const station = { v: 1, ws: "person:alice", seq: 1, prev: gh, at: 3, kind: "ws.station", body: { ws: "W", key: "dd".repeat(32) }, sig };
const chain = person_chain_js([station, g, admit], gh, crypto);
print(JSON.stringify({ hashes: chain.hashes, off: chain.off }));
print(JSON.stringify(roster_js("W", gh, [chain.entries], crypto)));
print(tie_of_js(gh, key, crypto));
