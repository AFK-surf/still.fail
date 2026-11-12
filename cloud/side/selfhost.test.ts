// A self-hosted cloud (selfhost/) as it runs: built, on workerd, reached over its own socket, signing people in through
// an SMTP relay that will speak only after STARTTLS and only to who authenticates, and through an OpenID provider of its
// own; both with certificates of a CA only EXTRA_CA_CERTS names. Real processes and sockets: the side run's
// (scripts/side.sh selfhost). Needs openssl.
import assert from "node:assert/strict";
import { execFileSync, spawn, type ChildProcess } from "node:child_process";
import { createServer as createHttps } from "node:https";
import { createServer as createNet, type Server, type Socket } from "node:net";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import { TLSSocket } from "node:tls";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { digest, randomSecret, type Tokens } from "../src/auth.ts";

const dir = mkdtempSync(join(tmpdir(), "selfhost-side-"));
const CLOUD = join(import.meta.dirname, "..");
const SMTP_USER = "cloud", SMTP_PASSWORD = "a password with spaces";
const mails: { from: string; to: string; data: string; tls: boolean; user: string }[] = [];
const servers: Server[] = [];
let workerd: ChildProcess | null = null;
let origin = "", issuer = "";

/** A port nothing listens on now. */
async function freePort(): Promise<number> {
  const server = createNet().listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  const port = (server.address() as { port: number }).port;
  await new Promise((resolve) => server.close(resolve));
  return port;
}

/** A CA, and a certificate of it for localhost. */
function certificates() {
  const ssl = (...args: string[]) => execFileSync("openssl", args, { cwd: dir, stdio: "pipe" });
  ssl("req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes", "-keyout", "ca.key", "-out", "ca.pem", "-days", "2", "-subj", "/CN=side CA");
  ssl("req", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes", "-keyout", "host.key", "-out", "host.csr", "-subj", "/CN=localhost");
  writeFileSync(join(dir, "host.ext"), "subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n");
  ssl("x509", "-req", "-in", "host.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial", "-out", "host.pem", "-days", "2", "-extfile", "host.ext");
  return { ca: readFileSync(join(dir, "ca.pem")), key: readFileSync(join(dir, "host.key")), cert: readFileSync(join(dir, "host.pem")) };
}

/** An SMTP relay: STARTTLS first, then AUTH PLAIN, then the mail. */
function smtp(tls: { key: Buffer; cert: Buffer }): Server {
  return createNet((plain) => {
    let socket: Socket | TLSSocket = plain, secure = false, user = "", from = "", to = "", data: string | null = null, buffer = "";
    const say = (line: string) => socket.write(`${line}\r\n`);
    const on = (chunk: Buffer) => {
      buffer += chunk.toString("latin1");
      for (let end; (end = buffer.indexOf("\r\n")) >= 0;) {
        const line = buffer.slice(0, end);
        buffer = buffer.slice(end + 2);
        if (data !== null) {
          if (line === ".") {
            mails.push({ from, to, data, tls: secure, user });
            data = null;
            say("250 queued");
          } else data += `${line.startsWith("..") ? line.slice(1) : line}\n`;
          continue;
        }
        const [verb = "", ...rest] = line.split(" ");
        const arg = rest.join(" ");
        if (verb === "EHLO") say(secure ? "250-localhost\r\n250 AUTH PLAIN" : "250-localhost\r\n250 STARTTLS");
        else if (verb === "STARTTLS" && !secure) {
          say("220 go on");
          plain.removeListener("data", on);
          socket = new TLSSocket(plain, { isServer: true, ...tls });
          secure = true;
          socket.on("data", on);
          return;
        } else if (!secure) say("530 STARTTLS first");
        else if (verb === "AUTH" && rest[0] === "PLAIN") {
          const [, name, password] = Buffer.from(rest[1] ?? "", "base64").toString().split("\0");
          if (name === SMTP_USER && password === SMTP_PASSWORD) (user = name, say("235 ok"));
          else say("535 no");
        } else if (!user) say("530 authenticate first");
        else if (verb === "MAIL") (from = arg, say("250 ok"));
        else if (verb === "RCPT") (to = arg, say("250 ok"));
        else if (verb === "DATA") (data = "", say("354 go on"));
        else if (verb === "QUIT") (say("221 bye"), socket.end());
        else say("500 what");
      }
    };
    plain.on("data", on);
    say("220 localhost side SMTP");
  });
}

/** An OpenID provider that consents at once: /authorize sends the browser straight back with a code. */
async function provider(tls: { key: Buffer; cert: Buffer }, port: number): Promise<Server> {
  const { publicKey, privateKey } = await generateKeyPair("ES256");
  const jwk = { ...(await exportJWK(publicKey)), kid: "side", alg: "ES256", use: "sig" };
  const codes = new Map<string, { nonce: string; challenge: string; redirect: string }>();
  const at = `https://127.0.0.1:${port}`;
  return createHttps(tls, async (req, res) => {
    const url = new URL(req.url ?? "/", at);
    const json = (body: unknown) => res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(body));
    if (url.pathname === "/.well-known/openid-configuration") return json({ issuer: at, authorization_endpoint: `${at}/authorize`, token_endpoint: `${at}/token`, jwks_uri: `${at}/keys` });
    if (url.pathname === "/keys") return json({ keys: [jwk] });
    if (url.pathname === "/authorize") {
      const code = randomSecret();
      codes.set(code, { nonce: url.searchParams.get("nonce")!, challenge: url.searchParams.get("code_challenge")!, redirect: url.searchParams.get("redirect_uri")! });
      const back = new URL(url.searchParams.get("redirect_uri")!);
      back.searchParams.set("code", code);
      back.searchParams.set("state", url.searchParams.get("state")!);
      return res.writeHead(302, { location: back.href }).end();
    }
    if (url.pathname === "/token" && req.method === "POST") {
      let body = "";
      for await (const chunk of req) body += chunk;
      const form = new URLSearchParams(body);
      const code = codes.get(form.get("code") ?? "");
      codes.delete(form.get("code") ?? "");
      if (!code || form.get("redirect_uri") !== code.redirect || (await digest(form.get("code_verifier") ?? "")) !== code.challenge) return res.writeHead(400).end();
      const now = Math.floor(Date.now() / 1000);
      const id_token = await new SignJWT({ nonce: code.nonce, email: "frank@example.test", email_verified: true, name: "Frank" })
        .setProtectedHeader({ alg: "ES256", kid: "side" }).setSubject("CN=frank,O=side").setIssuer(at).setAudience("side-client").setIssuedAt(now).setExpirationTime(now + 300).sign(privateKey);
      return json({ id_token });
    }
    res.writeHead(404).end();
  });
}

before(async () => {
  const tls = certificates();
  const [smtpPort, oidcPort, httpPort, setupPort] = [await freePort(), await freePort(), await freePort(), await freePort()];
  servers.push(smtp(tls).listen(smtpPort, "127.0.0.1"), (await provider(tls, oidcPort)).listen(oidcPort, "127.0.0.1"));
  execFileSync(process.execPath, ["selfhost/build.ts", "--out", join(dir, "cloud"), "--no-sites"], { cwd: CLOUD, stdio: "pipe" });
  origin = `http://127.0.0.1:${httpPort}`;
  issuer = `https://127.0.0.1:${oidcPort}`;
  const { privateKey } = await generateKeyPair("EdDSA", { crv: "Ed25519", extractable: true });
  // (the cloud's environment, and nothing of this one's but PATH; wrangler's types narrow process.env's to the Worker's)
  const env: Record<string, string | undefined> = {
    PATH: process.env.PATH, TMPDIR: dir, STILLFAIL_DATA: join(dir, "data"), LISTEN: `127.0.0.1:${httpPort}`, SETUP_LISTEN: `127.0.0.1:${setupPort}`,
    PUBLIC_ORIGIN: origin, ADMIN_ORIGIN: `http://localhost:${httpPort}`, RELAY_URL: "https://relay.example.test",
    AUTH_SIGNING_KEY: randomSecret(), ADMIN_TOKEN: randomSecret(), GRANT_SIGNING_JWK: JSON.stringify({ ...(await exportJWK(privateKey)), kid: "side" }),
    EMAIL_FROM: "noreply@side.example.test", SMTP_URL: `smtp://${SMTP_USER}:${encodeURIComponent(SMTP_PASSWORD)}@127.0.0.1:${smtpPort}`,
    GOOGLE_CLIENT_ID: "side-client", OIDC_ISSUER: issuer, OIDC_NAME: "Side SSO",
    EXTRA_CA_CERTS: join(dir, "ca.pem"), OUTBOUND_ALLOW: "public,local",
  };
  workerd = spawn(join(dir, "cloud", "run"), [], { stdio: ["ignore", "inherit", "inherit"], env: env as never });
  for (let i = 0; ; i++) {
    const up = await fetch(`${origin}/healthz`).then((r) => r.ok, () => false);
    if (up) break;
    // (the side run's: a real process taking its time to listen)
    if (i > 100) throw new Error("workerd did not come up");
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
});

after(() => {
  workerd?.kill();
  for (const server of servers) server.close();
});

/** A browser's sign-in from its start: the page that asks how, its form, and the tokens at the end. */
async function signIn(choose: (post: (fields: Record<string, string>) => Promise<Response>) => Promise<Response>): Promise<Tokens> {
  const verifier = randomSecret(), callback = "http://127.0.0.1:32145/oauth/callback";
  const query = new URLSearchParams({ state: randomSecret(), redirect_uri: callback, code_challenge: await digest(verifier), code_challenge_method: "S256" });
  const start = await fetch(`${origin}/v1/auth/google/start?${query}`, { redirect: "manual" });
  const id = /action="\/v1\/auth\/login\/([A-Za-z0-9_-]{43})"/.exec(await start.text())![1];
  const cookie = start.headers.get("set-cookie")!.split(";")[0]!;
  const post = (fields: Record<string, string>) => fetch(`${origin}/v1/auth/login/${id}`, { method: "POST", redirect: "manual", headers: { "content-type": "application/x-www-form-urlencoded", origin, cookie }, body: new URLSearchParams({ csrf: cookie.split("=")[1]!, ...fields }) });
  const finished = await choose(post);
  assert.equal(finished.status, 302);
  const code = new URL(finished.headers.get("location")!).searchParams.get("code");
  const tokens = await fetch(`${origin}/v1/auth/token`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ code, code_verifier: verifier, redirect_uri: callback }) });
  assert.equal(tokens.status, 200);
  return (await tokens.json()) as Tokens;
}

test("a code mailed through the operator's relay, after STARTTLS and AUTH, signs in", async () => {
  const tokens = await signIn(async (post) => {
    assert.equal((await post({ via: "email", email: "grace@example.test" })).status, 200);
    const mail = mails.at(-1)!;
    assert.deepEqual([mail.from, mail.to, mail.tls, mail.user], ["FROM:<noreply@side.example.test>", "TO:<grace@example.test>", true, SMTP_USER]);
    assert.match(mail.data, /^Subject: =\?UTF-8\?B\?/m);
    const text = /Content-Type: text\/plain; charset=utf-8\nContent-Transfer-Encoding: base64\n\n([A-Za-z0-9+/=\n]+)\n--/.exec(mail.data)![1]!;
    const code = /\b(\d{6})\b/.exec(Buffer.from(text.replace(/\n/g, ""), "base64").toString())![1]!;
    return post({ via: "code", code });
  });
  assert.equal(tokens.email, "grace@example.test");
});

test("the operator's OpenID provider signs in, its endpoints found by discovery, its certificate trusted by EXTRA_CA_CERTS", async () => {
  const tokens = await signIn(async (post) => {
    const gone = await post({ via: "google" });
    const at = new URL(gone.headers.get("location")!);
    assert.equal(`${at.origin}${at.pathname}`, `${issuer}/authorize`);
    assert.equal(at.searchParams.get("client_id"), "side-client");
    // (the browser at the provider, which sends it back: its answer read without trusting its certificate here)
    const back = await new Promise<string>((resolve, reject) => {
      import("node:https").then(({ get }) => get(at, { ca: readFileSync(join(dir, "ca.pem")) }, (r) => resolve(r.headers.location!)).on("error", reject));
    });
    return fetch(back, { redirect: "manual", headers: { cookie: gone.headers.get("set-cookie")!.split(";")[0]! } });
  });
  assert.equal(tokens.email, "frank@example.test");
  assert.equal(tokens.subject, `oi-${(await digest(`${issuer}\0CN=frank,O=side`)).slice(0, 32)}`);
});
