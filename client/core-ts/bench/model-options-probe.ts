// A station with several accounts and many model spellings, made up here. Compare the same number of calls in Hermes.
import "../src/hosts/hermes-globals.ts";
import { choices, models } from "../src/views/models.ts";

const g = globalThis as any;
const ids = Array.from({ length: 60 }, (_, i) => `gpt-6-sol-${i}`);
const profiles = Array.from({ length: 4 }, (_, i) => ({
  id: `account-${i}`,
  name: `Account ${i}`,
  runtime: "codex",
  runtimes: i % 2 ? ["codex", "claude"] : ["codex"],
  models: ids.map((id, n) => n % 2 === i % 2 ? id : `openai/${id}`),
  quota: { state: "ok", windows: [{ label: "5 小时", usedPercent: i === 0 ? 100 : 30, resetsAt: 1_700_000_600_000 }] },
}));
const overview = { profiles };
const session = { runtime: "codex", profile: "account-0", model: ids[0] };
let checksum = 0;
function run(n: number): number {
  const before = Date.now();
  for (let i = 0; i < n; i++) {
    const all = models(overview, 1_700_000_000_000);
    const own = choices(overview, session, 1_700_000_000_000);
    checksum += all.length + own.length + all[0].accounts.codex.length + own[0].accounts.codex.length;
  }
  return Date.now() - before;
}
run(1);
let count = Number(g.__benchCount ?? 0);
if (count === 0) {
  count = 1;
  while (run(count) < 250) count *= 2;
}
checksum = 0;
const ms = [run(count), run(count), run(count)];
g.print(`calls=${count} accounts=${profiles.length} models=${ids.length} ms=${ms.join(",")} checksum=${checksum}`);
