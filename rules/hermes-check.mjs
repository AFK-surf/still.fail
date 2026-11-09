// The rules' JS run in Hermes, as the core is (bundled by esbuild into one script): the vector's text as Node gets it.
import { canonical_of, entry_text_of, lower_role } from "./js/rules.js";
const vector = { v: 1, ws: "01HZZZZZZZZZZZZZZZZZZZZZZZ", seq: 3, prev: "ab".repeat(32), at: 1700000000, kind: "device", body: { sub: "s", id: "cd".repeat(32), kind: "web", label: "Chrome · 名字 😀 \u0000", exp: 1702592000 } };
print(entry_text_of(vector));
print(canonical_of(JSON.parse('{"b":[1,2,{"z":null,"a":"\\ud800x"}],"a":1.5}')));
print(canonical_of(JSON.parse('{"b":[1,2,{"z":null,"a":"\\ud800x"}],"a":-9007199254740991}')));
print(lower_role("owner", "member"));
