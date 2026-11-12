// Moves one cloud's accounts into another (cloud/src/move.ts says the whole of it): the icons the first keeps in its
// bucket, then its Directory and each account's object, into the second, both deployed with MOVING and the second
// with the first's keys. Says only counts, never what an account is.
//   MOVE_FROM=https://app.still.fail MOVE_TO=https://app.monoid.build MOVE_ADMIN_TOKEN=… node scripts/move-cloud.ts [--dry-run]
// --dry-run reads all of the first and says what it would write, writing nothing.
const from = process.env.MOVE_FROM?.replace(/\/+$/, "");
const to = process.env.MOVE_TO?.replace(/\/+$/, "");
const token = process.env.MOVE_ADMIN_TOKEN;
const dry = process.argv.includes("--dry-run");
if (!from || !to || !token) {
  console.error("MOVE_FROM, MOVE_TO and MOVE_ADMIN_TOKEN are needed");
  process.exit(2);
}
const auth = { authorization: `Bearer ${token}` };

async function call(url: string, init: RequestInit = {}): Promise<Response> {
  const response = await fetch(url, { ...init, headers: { ...auth, ...(init.headers ?? {}) } });
  if (!response.ok) throw new Error(`${init.method ?? "GET"} ${url}: ${response.status} ${(await response.text()).slice(0, 200)}`);
  return response;
}

const { icons } = (await (await call(`${from}/v1/admin/move/icons`)).json()) as { icons: string[] };
console.log(`icons: ${icons.length}`);
for (const name of icons) {
  const icon = await fetch(`${from}/v1/icons/${name}`);
  if (!icon.ok) throw new Error(`icon ${name}: ${icon.status}`);
  const body = await icon.arrayBuffer();
  if (!dry) await call(`${to}/v1/admin/move/icons/${name}`, { method: "PUT", headers: { "content-type": icon.headers.get("content-type") ?? "application/octet-stream" }, body });
}
const moved = await (await call(`${from}/v1/admin/move/export`, { method: "POST" })).text();
const parsed = JSON.parse(moved) as { directory: Record<string, unknown[]>; accounts: Record<string, unknown> };
console.log(`read: ${Object.entries(parsed.directory).map(([t, rows]) => `${t} ${rows.length}`).join(", ")}; accounts' objects ${Object.keys(parsed.accounts).length}; ${moved.length} bytes`);
if (dry) {
  console.log("dry run: nothing written");
  process.exit(0);
}
const written = (await (await call(`${to}/v1/admin/move/import`, { method: "POST", headers: { "content-type": "application/json" }, body: moved })).json()) as { tables: Record<string, number>; accounts: number };
console.log(`written: ${Object.entries(written.tables).map(([t, n]) => `${t} ${n}`).join(", ")}; accounts' objects ${written.accounts}`);
for (const [table, rows] of Object.entries(parsed.directory)) {
  if (written.tables[table] !== rows.length) throw new Error(`${table}: read ${rows.length}, written ${written.tables[table]}`);
}
if (written.accounts !== Object.keys(parsed.accounts).length) throw new Error("accounts' objects: not all written");
console.log("moved");
