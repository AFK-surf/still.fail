// The browser of CI's Windows run (e2e/win.sh), standing in for the person: the app's BROWSER (browser.cmd). It takes
// the login page the app opens, goes through the local cloud's sign-in as a browser does (its cookie, the sign-in
// page's choice of Google when it asks), Google's own page answered by the dev cloud as alice choosing herself
// (/__dev/google, cloud/test/dev.ts), and follows the cloud's redirect back to the app's loopback address, which sends
// it on to the cloud's page saying it is signed in (/v1/auth/done), whose page it keeps. Each step goes to
// E2E_BROWSER_LOG; the page it ended on is the last line (BACK <status> <words>).
import { appendFileSync } from "node:fs";

const say = (s) => {
  console.log(s);
  if (process.env.E2E_BROWSER_LOG) appendFileSync(process.env.E2E_BROWSER_LOG, s + "\n");
};
let url = new URL(process.argv[2]);
const cloud = url.origin;
let cookie = "";
try {
  for (let step = 0; step < 12; step++) {
    const ours = url.origin === cloud;
    say(`GET ${url.origin}${url.pathname}`);
    let r = await fetch(url, { redirect: "manual", headers: ours && cookie ? { cookie } : {} });
    if (ours) for (const c of r.headers.getSetCookie()) cookie = c.split(";")[0];
    if (r.status === 200 && ours && url.pathname !== "/v1/auth/done") {
      // the page that asks how to sign in (when the cloud offers email too): Google, as a person picks it
      const page = await r.text();
      const id = /action="\/v1\/auth\/login\/([A-Za-z0-9_-]{43})"/.exec(page)?.[1];
      if (!id) throw new Error(`a page with no sign-in on it at ${url.pathname}`);
      r = await fetch(`${cloud}/v1/auth/login/${id}`, {
        method: "POST", redirect: "manual",
        headers: { "content-type": "application/x-www-form-urlencoded", origin: cloud, cookie },
        body: new URLSearchParams({ csrf: cookie.split("=")[1] ?? "", via: "google" }).toString(),
      });
      for (const c of r.headers.getSetCookie()) cookie = c.split(";")[0];
    }
    if (r.status >= 300 && r.status < 400) {
      let next = new URL(r.headers.get("location"), url);
      if (next.hostname === "accounts.google.com") next = new URL(`${cloud}/__dev/google${next.search}&user=alice`);
      url = next;
      continue;
    }
    const words = (await r.text()).replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
    say(`BACK ${r.status} ${url.origin}${url.pathname}: ${words}`);
    process.exit(r.status === 200 ? 0 : 1);
  }
  throw new Error("too many redirects");
} catch (e) {
  say(`BROWSER FAILED ${e?.message ?? e}`);
  process.exit(1);
}
