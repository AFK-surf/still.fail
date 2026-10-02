# Station decision models

`decision` in station `config.json` configures a reusable typed-choice client. Its first caller reviews both `chat_post all_done` and `chat_state all_done` (including legacy `final`) before posting, attaching files or changing state. Absent configuration preserves older station behavior.

```json
{
  "decision": {
    "provider": "jev",
    "endpoint": "https://api.typesafe.ai/v1/systemone",
    "model": "jev-latest",
    "keyEnv": "TYPESAFE_API_KEY",
    "mode": "shadow",
    "threshold": 0.85
  }
}
```

The named credential environment variable must be available to the **station**, not just an agent subprocess. Keys are never included in configuration or audit records. Endpoint redirects are disabled; HTTPS is required except for loopback development services. No provider is enabled automatically and no existing runtime login is reused.

For a model supporting Chat Completions logprobs, set `provider` to `chat_logprobs`, the full endpoint (for example `https://api.openai.com/v1/chat/completions`), a model such as `gpt-6-luna`, and `keyEnv` to `OPENAI_API_KEY`. The request uses `reasoning_effort: none`, one completion token and `top_logprobs: 20`. Compatibility must be checked against the selected endpoint; an unsupported parameter is a failed check, never a generated confidence fallback. Raw logits are not exposed by this adapter: it uses token log probabilities. These are not calibrated task correctness probabilities.

A question supplies instructions and 2–20 named criteria. Jev returns native choice probabilities. The chat adapter maps choices to letters, requires every letter in the returned top-logprobs, rejects retained mass below 95%, then normalizes that mass. Missing choices, invalid numbers, malformed distributions, timeouts (12 seconds) and excessive inputs/responses fail explicitly. No conversation evidence is silently truncated.

## Completion review

Inputs contain up to 200 complete messages per session conversation, their author/role, pending cards, the proposed post and completion evidence. All session threads are checked because endings belong to the session. Attachments are marked as present; their contents and private runtime/tool transcripts are **not** read. This checks consistency of visible claims, not whether a claimed commit actually exists. More than 200 messages or a request larger than 96 KB abstains; future retrieval must preserve unresolved obligations before extending this limit.

The four choices are `complete`, `agent_work`, `human_needed`, `uncertain`. Factual answers need no invented follow-up approval. Already resolved questions must stay resolved. The model sees conversation text as untrusted evidence. A concurrent conversation update invalidates the result.

- `shadow` (default): run and record the check without changing the agent's ending. Use this to evaluate false positives on representative cases before enabling enforcement.
- `enforce`: accept only `complete` at or above the threshold. Other outcomes return a tool error before side effects; the agent must reconcile the evidence and continue or ask a real outstanding question. A provider outage/uncertainty is not proof that work remains. Existing bounded missing-state nudges apply; no automatic human question or model retry loop is added.

SQLite `decision_checks` stores session, timestamp, mode, provider, model, input thread revisions, latency, probabilities, retained mass and errors. It does not store conversation text or secrets. `accepted` records the review outcome, including in shadow mode; it is not a claim that a post landed. The table is additive (`IF NOT EXISTS`), without a schema-version bump. Read examples:

```sql
SELECT session, created_at, json_extract(result, '$.accepted'), result
FROM decision_checks ORDER BY id DESC LIMIT 50;
```

The 0.85 threshold is an initial policy setting, **not** calibrated on still.fail conversations. Integration tests use a loopback deterministic provider and verify blocking, allowing, legacy compatibility, provider errors and shadow behavior; they do not establish model accuracy. Do not enable enforce fleet-wide without evaluating real representative labeled cases.

## References

- Studio reference: `router-decision-dataset/general-eval/sources/jevbench/jevbench/adapters/typesafe.py` (native choice transport), and `decisionbench` (non-generative decisions).
- [TypeSafe API](https://api.typesafe.ai/redoc)
- [OpenAI GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna)

No independent Luna typed-decision endpoint was verified; Luna uses the Chat Completions adapter above.
