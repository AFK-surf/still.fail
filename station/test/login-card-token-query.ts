// Candidate keys for the literal `"login":"<id>"` searched by closeLoginCards. SQLite's default LIKE folds ASCII
// case; lower() does the same. The final lookup must still check the original card and all other predicates.
// A card can be older, malformed, or contain more than one such field, so do not assume a single JSON property.
export const LOGIN_CARD_TOKENS = `WITH RECURSIVE fragments(rest) AS (
  SELECT lower(?1)
  UNION ALL
  SELECT substr(rest, instr(rest, '"login":"') + 9) FROM fragments WHERE instr(rest, '"login":"') > 0
), tails(tail) AS (
  SELECT substr(rest, instr(rest, '"login":"') + 9) FROM fragments WHERE instr(rest, '"login":"') > 0
)
SELECT DISTINCT substr(tail, 1, instr(tail, '"') - 1) AS login FROM tails WHERE instr(tail, '"') > 0`;
