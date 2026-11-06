import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { LOGIN_CARD_TOKENS } from "./login-card-token-query.ts";

test("login keys preserve the existing card substring match for station login IDs", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const tokens = db.prepare(LOGIN_CARD_TOKENS);
    const match = db.prepare(`SELECT ?1 LIKE '%"login"%' AND ?1 LIKE ?2 AS matches`);
    const cards = [null, "", JSON.stringify({ type: "login", login: "abc123" }),
      JSON.stringify({ type: "login", login: "other", text: '"login":"abc123"' }),
      '{"LOGIN":"ABC123","nested":{"login":"second"}}',
      '{"login":"abc123","login":"second"}', 'broken "login":"abc123" and "login":"second"',
      '{"login":"abc123', '{"login" : "abc123"}', '{"login":"abc1234"}',
      '{"login":"a\\"b","login":"abc123"}'];
    cards.push('before\0"login":"abc123"', '"login":"abc123"\0"login":"second"');
    for (const card of cards) {
      const keys = new Set(tokens.all(card).map((row) => row.login));
      for (const login of ["abc123", "ABC123", "second", "missing", "abc12"]) {
        const expected = (match.get(card, `%"login":"${login}"%`) as { matches: number | null }).matches === 1;
        assert.equal(keys.has(login.toLowerCase()), expected, `${JSON.stringify(card)} / ${login}`);
      }
    }
    const many = Array.from({ length: 400 }, (_, i) => `"login":"old${i}"`).join(",");
    assert.equal(tokens.all(many).length, 400);
  } finally { db.close(); }
});
