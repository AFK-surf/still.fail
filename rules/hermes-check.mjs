// The rules' JS run in Hermes, as the core is (bundled by esbuild into one script): the vector's text as Node gets it.
import { body_hash_js, body_refusal_js, canonical_of, entry_text_of, lower_role, person_chain_js, roster_js, state4_js, tie_of_js, ws_tag_js } from "./js/rules.js";
const vector = { v: 1, ws: "01HZZZZZZZZZZZZZZZZZZZZZZZ", seq: 3, prev: "ab".repeat(32), at: 1700000000, kind: "device", body: { sub: "s", id: "cd".repeat(32), kind: "web", label: "Chrome · 名字 😀 \u0000", exp: 1702592000 } };
print(entry_text_of(vector));
print(canonical_of(JSON.parse('{"b":[1,2,{"z":null,"a":"\\ud800x"}],"a":1.5}')));
print(canonical_of(JSON.parse('{"b":[1,2,{"z":null,"a":"\\ud800x"}],"a":-9007199254740991}')));
print(lower_role("owner", "member"));
// A person log that branches, its active chain and the workspace's list and state from it and the bodies its
// commitments name (src/lock/chain.mbt, body.mbt, roster.mbt, state4.mbt), with a stand-in for the cryptography
// (Hermes has none of node's): only what Hermes and Node print of the same is compared.
const fnv = (s, seed) => { let h = seed >>> 0; for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619) >>> 0; return h.toString(16).padStart(8, "0"); };
const crypto = { sha256Hex: (s) => [1, 2, 3, 4, 5, 6, 7, 8].map((k) => fnv(s, 2166136261 + k)).join(""), sigValid: () => true, validKeyId: () => true, endpointProof: () => false };
const hash = (e) => crypto.sha256Hex(entry_text_of(e));
const key = "ed25519:" + "aa".repeat(32), sig = { key, alg: "Ed25519", sig: "00" };
const g = { v: 1, ws: "person:alice", seq: 0, prev: null, at: 1, kind: "genesis", body: { sub: "alice", device: { key, id: "bb".repeat(32), label: "app" } }, sig };
const gh = hash(g);
const tag = ws_tag_js("W", gh, crypto);
const open = { ws: "W", kind: "open", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] }, email: "a@x", prev: null, salt: "0f".repeat(16) };
const admitBody = { ws: "W", kind: "member", sub: "bob", email: "bob@x", lock: "cc".repeat(32), role: "admin", prev: body_hash_js(open, crypto), salt: "1e".repeat(16) };
const stationBody = { ws: "W", kind: "station", key: "dd".repeat(32), prev: body_hash_js(open, crypto), salt: "2d".repeat(16) };
const opened = { v: 1, ws: "person:alice", seq: 1, prev: gh, at: 2, kind: "ws", body: { t: tag, h: body_hash_js(open, crypto) }, sig };
const oh = hash(opened);
const admit = { v: 1, ws: "person:alice", seq: 2, prev: oh, at: 3, kind: "ws", body: { t: tag, h: body_hash_js(admitBody, crypto) }, sig };
const station = { v: 1, ws: "person:alice", seq: 2, prev: oh, at: 4, kind: "ws", body: { t: tag, h: body_hash_js(stationBody, crypto) }, sig };
const web = { v: 1, ws: "person:alice", seq: 2, prev: oh, at: 5, kind: "web", body: { id: "ee".repeat(32), label: "a browser", exp: 5 + 86400 }, sig };
const chain = person_chain_js([station, g, web, admit, opened], gh, crypto);
print(JSON.stringify({ hashes: chain.hashes, off: chain.off }));
print(JSON.stringify(body_refusal_js("W", admitBody, [{ genesis: gh, chain: [g, opened, admit] }], crypto)));
print(JSON.stringify(roster_js("W", gh, [chain.entries], [stationBody, open, admitBody], [], crypto)));
print(JSON.stringify(roster_js("W", gh, [chain.entries], [stationBody, open, admitBody], [body_hash_js(admitBody, crypto)], crypto)));
print(JSON.stringify(state4_js("W", gh, [chain.entries], [stationBody, open, admitBody], 100, crypto).state));
print(tie_of_js(gh, key, crypto));
