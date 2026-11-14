// still.fail cloud's workerd config (capnp), made from the wrangler files as Cloudflare reads them: the API
// (wrangler.jsonc: its Durable Objects, SQLite on a local disk; its bucket and email, stand-ins of this directory), the
// static sites (wrangler.web/admin/preview.jsonc: their files on disk, served as their `assets` say), and in front of
// them the router, which sends each request to the Worker the routes give its host and path. What names the cloud
// (its origins, its relay, its admin, its sign-in) is read from the environment as workerd starts (fromEnvironment), so
// one build is any cloud's: nothing of still.fail's hosted service's is put in (the vars that name its hosts or relays
// are read from the environment like the rest, and are unset unless the operator sets them). README.md says the
// variables; build.ts writes this beside the bundles it embeds.
//   node selfhost/config.ts > config.capnp
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { parse } from "jsonc-parser";

const CLOUD = join(import.meta.dirname, "..");

/** A wrangler file as it is. */
type Wrangler = {
  name: string;
  main?: string;
  compatibility_date: string;
  compatibility_flags?: string[];
  routes?: { pattern: string; zone_name?: string; custom_domain?: boolean }[];
  vars?: Record<string, unknown>;
  assets?: { directory: string; binding?: string; not_found_handling?: string; html_handling?: string };
  durable_objects?: { bindings: { name: string; class_name: string; script_name?: string }[] };
  migrations?: { tag: string; new_sqlite_classes?: string[] }[];
  r2_buckets?: { binding: string }[];
  send_email?: { name: string }[];
};

export const wrangler = (file: string): Wrangler => parse(readFileSync(join(CLOUD, file), "utf8"));

/** The static sites, by the Worker the router names them (and the directory their files are copied to, build.ts). */
export const SITES = { web: "wrangler.web.jsonc", admin: "wrangler.admin.jsonc", preview: "wrangler.preview.jsonc" } as const;
export type Site = keyof typeof SITES;
/** Which of the cloud's hosts a request is on: PUBLIC_ORIGIN's, ADMIN_ORIGIN's or PREVIEW_ORIGIN's. */
export type Role = "public" | "admin" | "preview";
/** A route: on a host, a path (a prefix where it ends in *; any with "*"), to a Worker. */
export type Route = { role: Role; path: string; to: "api" | Site };

/**
 * What deploy.py puts as the API's secrets, and what a self-hosted cloud sets besides the vars: each read from the
 * environment as well (env.ts says what each is).
 */
const SECRETS = ["GOOGLE_CLIENT_SECRET", "AUTH_SIGNING_KEY", "ADMIN_TOKEN", "GRANT_SIGNING_JWK", "FEEDBACK_TOKEN", "VAPID_PUBLIC_KEY", "VAPID_PRIVATE_KEY", "VAPID_SUBJECT", "FCM_SERVICE_ACCOUNT", "APNS_KEY", "AXIOM_TOKEN", "AXIOM_DATASET", "REVIEW_ACCOUNTS", "ADMIN_EMAIL", "RELAY_URL", "OIDC_ISSUER", "OIDC_NAME"];

/**
 * The cloud's routes from the wrangler files. Each static site's first custom domain is its host (app.still.fail the
 * web app's, PUBLIC_ORIGIN; admin.still.fail the console's, ADMIN_ORIGIN; preview.still.fail the preview host's); a
 * route's host is the role of the site whose host it is, and one of no site's (the old names, the test channel's) is
 * not this cloud's. A site's custom domain takes every path the routes leave on its host. The relay's routes are not
 * here: a self-hosted cloud's relay is iroh-relay itself, at RELAY_URL.
 */
export function routes(): Route[] {
  const ROLE: Record<Site, Role> = { web: "public", admin: "admin", preview: "preview" };
  const sites = Object.fromEntries((Object.keys(SITES) as Site[]).map((site) => [site, wrangler(SITES[site])])) as Record<Site, Wrangler>;
  const roles = new Map((Object.keys(SITES) as Site[]).map((site) => [sites[site].routes!.find((r) => r.custom_domain)!.pattern, ROLE[site]]));
  const of = (to: Route["to"], config: Wrangler): Route[] =>
    (config.routes ?? []).flatMap((r) => {
      const slash = r.pattern.indexOf("/");
      const role = roles.get(slash < 0 ? r.pattern : r.pattern.slice(0, slash));
      return role ? [{ role, path: r.custom_domain ? "*" : r.pattern.slice(slash), to }] : [];
    });
  // (the routes first: they take precedence over a custom domain, as on Cloudflare)
  const all = [...of("api", wrangler("wrangler.jsonc")), ...(Object.keys(SITES) as Site[]).flatMap((site) => of(site, sites[site]))];
  return all.sort((a, b) => Number(a.path === "*") - Number(b.path === "*"));
}

/** The names a Worker reads from the environment: its string vars (an object var, RELAY_NAMES say, is not: the
 * environment holds text) and, for the API, the secrets. */
export function fromEnvironment(config: Wrangler, secrets: boolean): string[] {
  const vars = Object.entries(config.vars ?? {}).filter(([, v]) => typeof v === "string").map(([k]) => k);
  return [...new Set([...vars, ...(secrets ? SECRETS : [])])];
}

const text = (value: string) => JSON.stringify(value);
const fromEnv = (names: string[]) => names.map((name) => `(name = ${text(name)}, fromEnvironment = ${text(name)})`);
const json = (name: string, value: unknown) => `(name = ${text(name)}, json = ${text(JSON.stringify(value))})`;
const flags = (config: Wrangler) => `compatibilityDate = ${text(config.compatibility_date)}, compatibilityFlags = [${(config.compatibility_flags ?? []).map(text).join(", ")}]`;
const module = (file: string) => `modules = [(name = ${text(file)}, esModule = embed ${text(`workers/${file}`)})]`;

/** The workerd config: the router on the `http` socket, setup.ts on `setup`; directories (`objects`, `releases`, the
 * sites') and both sockets' addresses are the defaults the run script overrides (--directory-path, --socket-addr), and
 * /site.capnp (where the API may connect, what TLS it trusts) is the one it writes. */
export function workerdConfig(): string {
  const api = wrangler("wrangler.jsonc");
  const local = (api.durable_objects?.bindings ?? []).filter((b) => !b.script_name);
  const sqlite = new Set((api.migrations ?? []).flatMap((m) => m.new_sqlite_classes ?? []));
  const origins = ["PUBLIC_ORIGIN", "PUBLIC_ORIGIN_ALIASES", "ADMIN_ORIGIN", "BETA_ORIGIN", "PREVIEW_ORIGIN"];
  const services = [
    `(name = "router", worker = (${module("router.js")}, ${flags(api)}, bindings = [${[...fromEnv(["PUBLIC_ORIGIN", "ADMIN_ORIGIN", "PREVIEW_ORIGIN"]), json("ROUTES", routes()), `(name = "API", service = "api")`, ...(Object.keys(SITES).map((s) => `(name = ${text(s.toUpperCase())}, service = ${text(s)})`))].join(", ")}]))`,
    `(name = "api", worker = (${module("api.js")}, ${flags(api)}, bindings = [${[
      ...fromEnv(fromEnvironment(api, true)),
      ...local.map((b) => `(name = ${text(b.name)}, durableObjectNamespace = ${text(b.class_name)})`),
      ...(api.r2_buckets ?? []).map((b) => `(name = ${text(b.binding)}, service = (name = "releases", entrypoint = "Releases"))`),
      ...(api.send_email ?? []).map((b) => `(name = ${text(b.name)}, service = (name = "mail", entrypoint = "Mail"))`),
    ].join(", ")}], durableObjectNamespaces = [${local.map((b) => `(className = ${text(b.class_name)}, uniqueKey = ${text(`${api.name}-${b.class_name}`)}, enableSql = ${sqlite.has(b.class_name)})`).join(", ")}], durableObjectStorage = (localDisk = "objects"), globalOutbound = "internet"))`,
    ...(Object.keys(SITES) as Site[]).map((site) => {
      const config = wrangler(SITES[site]);
      const assets = config.assets!;
      return `(name = ${text(site)}, worker = (${module("static.js")}, ${flags(config)}, bindings = [${[...fromEnv(origins), json("SITE", site), json("HANDLING", { html: assets.html_handling ?? "auto-trailing-slash", notFound: assets.not_found_handling ?? "none" }), `(name = "FILES", service = ${text(`${site}-files`)})`].join(", ")}], globalOutbound = "none"))`;
    }),
    `(name = "releases", worker = (${module("releases.js")}, ${flags(api)}, bindings = [(name = "FILES", service = "releases-files")], globalOutbound = "none"))`,
    // (the mail's own way out, to the SMTP relay the operator names, which may be on their own network; the API's
    // reaches only public addresses, so nothing it is asked to fetch reaches the machine's own)
    `(name = "mail", worker = (${module("mail.js")}, ${flags(api)}, bindings = [${fromEnv(["SMTP_URL", "SMTP_HELO"]).join(", ")}], globalOutbound = "smtp"))`,
    `(name = "setup", worker = (${module("setup.js")}, ${flags(api)}, bindings = [${[...fromEnv(["PUBLIC_ORIGIN", "ADMIN_TOKEN"]), `(name = "API", service = "api")`, `(name = "ACCOUNTS", durableObjectNamespace = (className = "Account", serviceName = "api"))`, `(name = "DIRECTORY", durableObjectNamespace = (className = "Directory", serviceName = "api"))`].join(", ")}], globalOutbound = "none"))`,
    ...(Object.keys(SITES) as Site[]).map((site) => `(name = ${text(`${site}-files`)}, disk = (path = ${text(`sites/${site}`)}))`),
    `(name = "releases-files", disk = (path = "data/releases", writable = true))`,
    `(name = "objects", disk = (path = "data/objects", writable = true))`,
    // (what the API may reach, and the certificates both trust beside the browsers', are the operator's: `run` writes
    // them as /site.capnp, from OUTBOUND_ALLOW, OUTBOUND_DENY and EXTRA_CA_CERTS)
    `(name = "internet", network = (allow = Site.allow, deny = Site.deny, tlsOptions = (trustBrowserCas = true, trustedCertificates = Site.trusted)))`,
    `(name = "smtp", network = (allow = ["public", "private", "local"], deny = Site.deny, tlsOptions = (trustBrowserCas = true, trustedCertificates = Site.trusted)))`,
    `(name = "none", network = (allow = []))`,
  ];
  return [
    "# Made by cloud/selfhost/config.ts from the wrangler files; not edited.",
    'using Workerd = import "/workerd/workerd.capnp";',
    'using Site = import "/site.capnp";',
    "const config :Workerd.Config = (",
    `  services = [\n    ${services.join(",\n    ")}\n  ],`,
    '  sockets = [(name = "http", address = "127.0.0.1:8080", http = (forwardedProtoHeader = "X-Forwarded-Proto"), service = "router"), (name = "setup", address = "127.0.0.1:8081", http = (), service = "setup")],',
    ");",
    "",
  ].join("\n");
}

if (import.meta.main) process.stdout.write(workerdConfig());
