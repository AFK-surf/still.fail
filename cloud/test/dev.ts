// A local ember cloud for trying the whole path without Cloudflare: the
// Worker in miniflare (Google mocked), one signed-in account with a
// workspace, and a helper that hands out grants to a browser page.
//   RELAY=http://127.0.0.1:3340 pnpm exec tsx test/dev.ts
// Prints the enrollment command for a station; GET http://127.0.0.1:8788/grant?device=<hex>
// returns a grant for the first enrolled station.
import { createServer } from "node:http";
import { harness } from "./harness.ts";

const origin = "http://127.0.0.1:8787";
const h = await harness({ origin, port: 8787, relayUrl: process.env.RELAY ?? "http://127.0.0.1:3340" });
const alice = h.as(await h.login("alice"));
const workspace = await (await alice("POST", "/v1/workspaces", { name: "Dev" })).json() as { id: string };
const enrollment = await (await alice("POST", `/v1/workspaces/${workspace.id}/enrollments`, { name: "dev-station" })).json() as { command: string };
console.log(`ENROLL ${enrollment.command}`);

createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", "http://helper");
  const headers = { "access-control-allow-origin": "*", "content-type": "application/json" };
  const view = await (await alice("GET", `/v1/workspaces/${workspace.id}`)).json() as { stations: { id: string }[] };
  const station = view.stations[0];
  if (!station) return void res.writeHead(409, headers).end(JSON.stringify({ error: "no station enrolled yet" }));
  const granted = await alice("POST", `/v1/workspaces/${workspace.id}/stations/${station.id}/grant`, { device: url.searchParams.get("device") });
  res.writeHead(granted.status, headers).end(await granted.text());
}).listen(8788, "127.0.0.1", () => console.log("READY grant helper on :8788"));
