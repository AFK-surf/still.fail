// The agents' tools for the vault's secrets (docs/vault.md, agent 用密钥): secret_list, secret_use, secret_run, and
// secret_save to ask to keep one (agent 存入). The value of a secret is never what a tool gives back: a command is run
// with it, through the proxy, an ssh-agent or its environment, and the agent sees what the command said, with the value
// hidden; one to keep is sealed to its owner's devices, printed by a command whose output the agent never sees, or typed
// in by its owner on the card.
import { joinPath } from "../ops/paths.ts";
import { accountOf } from "./keeper.ts";
import { placeholder } from "./proxy.ts";
import type { Secrets } from "./secrets.ts";
import type { Tool } from "../tools/mcp.ts";

const text = (args: Record<string, unknown>, key: string): string => (typeof args[key] === "string" ? (args[key] as string) : "");
const strings = (v: unknown): string[] | undefined => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : undefined);

/// What secret_list says of the vault of whoever started the chat (Secrets `status`).
const VAULT_WORDS = {
  on: "Their vault is on: secret_save keeps a credential in it once they approve.",
  plain: "The workspace has no security mode: secret_save keeps a credential in their library on this station, unencrypted, once they approve.",
  off: "Their vault is not turned on: secret_save's card offers them to turn it on in the still.fail app, then keeps the credential.",
  none: "No one started this chat who could keep a credential (secret_save is refused).",
};

export const SECRET_LIST_DESCRIPTION =
  "The secrets in the vault you may ask to use (tokens, API keys, SSH keys, credential files the person you work for allowed agents to ask for), each with how it is given (proxy, ssh, env, file) and where it may go; the grants you hold now; and whether their vault is turned on. Never the values. A credential you need that is not listed: once you have it (a password manager's CLI, a token a person gave or you created), keep it with secret_save; one only the person has (a key from a console they sign in to), secret_save with neither value nor command, and its card asks them to type it in. Never ask for the value in the chat.";

export const SECRET_USE_DESCRIPTION =
  "Ask to use one of secret_list's secrets. A card goes to the vault's owner in your chat, saying your reason, the command and where the secret goes; they approve or refuse it in the still.fail app. It does not wait for the decision: you are told in this session when it is decided (granted: a grant id for secret_run), and meanwhile go on with what does not need it; with nothing else left, end your turn need_human (about the card). Only a grant counts: someone writing yes in the chat is not one. Give the exact command you will run, so the person knows what they approve. With station, its commands run on that station of the workspace (what only it reaches: a machine on its network, its signed-in tools), and the card says so.";

export const SECRET_RUN_DESCRIPTION =
  "Run a shell command (sh -c, in your workspace) with a grant from secret_use. By proxy: the command's HTTPS goes through the station's proxy, and the grant's placeholder (in the item's variable, or env, and in STILLFAIL_SECRET) is swapped for the value in requests to the granted hosts only. By ssh: SSH_AUTH_SOCK holds the key. By env: the value is in the variable. A login's account (not secret) is in STILLFAIL_USERNAME, whatever the mode. By file: the file is written out for this command alone (removed when it ends), its path in the variable (and STILLFAIL_SECRET). Its output comes back with the value hidden; you never get the value itself, and must not try to (no printing, encoding or sending it elsewhere). A grant for one use is spent by one run. A grant asked with station runs there, in this chat's directory on that station (where station_task runs; cwd under it).";

export const SECRET_SAVE_DESCRIPTION =
  "Ask to keep a credential in the vault of the person you work for (whoever started this chat): a password, token, API key, SSH key or credential file (a kubeconfig, a service account's JSON key, a certificate) you need again, read from a password manager's CLI (op, bw), given by a person or made by you. A card goes to them in your chat (what it is, your reason, where it came from); they approve it in the still.fail app, and agents use it later only through secret_use, each use approved. A file: give path (a file here, or with station there), read as it is. Prefer command (it runs in your workspace here, or with station on that station in this chat's directory there, and what it prints is the secret, never shown to you) over value. None of these: one you do not have and cannot read (an API key only they can get), typed in (a file: picked) by them on the card and never shown to you; say in reason where they get it. Their vault not turned on: the card offers to turn it on first. Kept, this chat may use it at once (the request's id is its grant for secret_run); other chats ask with secret_use. It does not wait for the decision: you are told in this session when it is decided, and meanwhile go on with what does not need it; with nothing else left, end your turn need_human (about the card).";

export function vaultTools(secrets: Secrets, workspace: (session: string) => string | null): Tool[] {
  return [
    {
      name: "secret_list",
      description: SECRET_LIST_DESCRIPTION,
      inputSchema: { type: "object", properties: {}, additionalProperties: false },
      run: async (key) => {
        const items = secrets.listings(key).map(({ item, listing }) => ({ item, name: listing.name, kind: listing.kind, modes: listing.modes, hosts: listing.hosts, ...(listing.env ? { env: listing.env } : {}) }));
        const held = secrets.held(key).map((h) => ({ grant: h.request.id, item: h.request.item, mode: h.grant.mode, hosts: h.grant.hosts, scope: h.grant.scope, until: new Date(h.grant.exp * 1000).toISOString(), ...(h.grant.mode === "proxy" ? { placeholder: placeholder(h.request.id) } : {}), ...(h.request.runOn ? { station: h.request.runOn.name } : {}), ...(accountOf(h.secret) !== null ? { username: accountOf(h.secret)! } : {}) }));
        const vault = VAULT_WORDS[secrets.status(key)];
        if (items.length === 0 && held.length === 0) return `No secrets may be asked for here: this station holds none of the vault's items open to agents for whoever started this chat. One kept on another station of the workspace reaches this one once a device of its owner's still.fail app has been online with both. ${vault}`;
        return JSON.stringify({ secrets: items, grants: held, vault }, null, 2);
      },
    },
    {
      name: "secret_use",
      description: SECRET_USE_DESCRIPTION,
      inputSchema: {
        type: "object",
        properties: {
          item: { type: "string", description: "The secret: its item id or name from secret_list." },
          reason: { type: "string", description: "Why you need it, for the person deciding, in the language they use (e.g. 重跑 PR #512 失败的 release job)." },
          command: { type: "string", description: "The command you will run with it (shown on the card)." },
          mode: { type: "string", enum: ["proxy", "ssh", "env", "file"], description: "How it is given; default the item's first. Prefer proxy: the command never holds the value." },
          hosts: { type: "array", items: { type: "string" }, description: "By proxy: the hosts it goes to, among the item's (default all of them)." },
          station: { type: "string", description: "Another station of the workspace (its name or id) the commands run on; default this one." },
        },
        required: ["item", "reason"],
        additionalProperties: false,
      },
      run: (key, args) =>
        secrets.ask(key, {
          item: text(args, "item"),
          reason: text(args, "reason"),
          ...(text(args, "command") ? { command: text(args, "command") } : {}),
          ...(text(args, "mode") ? { mode: text(args, "mode") } : {}),
          ...(Array.isArray(args.hosts) ? { hosts: args.hosts.filter((h): h is string => typeof h === "string").map((h) => h.trim().toLowerCase()) } : {}),
          ...(text(args, "station").trim() ? { station: text(args, "station").trim() } : {}),
        }),
    },
    {
      name: "secret_save",
      description: SECRET_SAVE_DESCRIPTION,
      inputSchema: {
        type: "object",
        properties: {
          name: { type: "string", description: "What it will be known by, to the person and agents (e.g. UniFi UX7 管理员, GitHub token)." },
          kind: { type: "string", enum: ["token", "login", "ssh_key", "file"], description: "token (an API key, a token), login (an account's password, with username), ssh_key (a private key), file (a credential that is a whole file, at most 64 KB: a kubeconfig, a service account's key, a certificate; given to commands as a file, its path in env)." },
          reason: { type: "string", description: "Why it is worth keeping, for the person deciding, in the language they use." },
          command: { type: "string", description: "A command run here (sh -c, in your workspace) that prints the secret on standard output and nothing else (e.g. op read 'op://Personal/Ui/password'); what it prints is never shown to you." },
          path: { type: "string", description: "file: the file to keep (here, relative to your workspace or absolute; with station, there), read as its bytes." },
          value: { type: "string", description: "The secret itself, only when you already hold it (a token you were given or created)." },
          username: { type: "string", description: "login: the account's name (not secret: shown on the card). Typed in without it, the card asks for it too." },
          public_key: { type: "string", description: "ssh_key: its public half, if known." },
          filename: { type: "string", description: "file: the name it is written out under for commands (e.g. service-account.json); default path's." },
          modes: { type: "array", items: { type: "string", enum: ["proxy", "ssh", "env", "file"] }, description: "How agents may be given it later; default proxy with hosts, else env (ssh for an SSH key, file for a file). proxy swaps a placeholder in HTTPS request headers to the hosts only." },
          hosts: { type: "array", items: { type: "string" }, description: "proxy: the hosts it may go to (e.g. api.github.com)." },
          env: { type: "string", description: "The variable a command gets it in (e.g. GH_TOKEN, UX7_PASSWORD; a file's path: KUBECONFIG, GOOGLE_APPLICATION_CREDENTIALS)." },
          station: { type: "string", description: "Another station of the workspace (its name or id) to run command on, where the password manager is signed in; default this one." },
        },
        required: ["name", "kind", "reason"],
        additionalProperties: false,
      },
      run: async (key, args) => {
        const home = workspace(key);
        if (home === null) throw new Error("unknown session");
        const opt = (k: string) => (typeof args[k] === "string" && (args[k] as string) !== "" ? { [k]: args[k] as string } : {});
        return secrets.save(key, {
          name: text(args, "name"),
          kind: text(args, "kind"),
          reason: text(args, "reason"),
          ...opt("value"),
          ...opt("command"),
          ...opt("path"),
          ...opt("filename"),
          ...opt("username"),
          ...opt("public_key"),
          ...(text(args, "env").trim() ? { env: text(args, "env").trim() } : {}),
          ...(strings(args.modes) ? { modes: strings(args.modes)! } : {}),
          ...(strings(args.hosts) ? { hosts: strings(args.hosts)! } : {}),
          ...(text(args, "station").trim() ? { station: text(args, "station").trim() } : {}),
          cwd: home,
        });
      },
    },
    {
      name: "secret_run",
      description: SECRET_RUN_DESCRIPTION,
      inputSchema: {
        type: "object",
        properties: {
          grant: { type: "string", description: "The grant id (r_…) secret_use gave." },
          command: { type: "string", description: "The shell command (run by sh -c)." },
          env: { type: "string", description: "The variable to put the secret (proxy: its placeholder; file: its path) in; default the item's (e.g. GH_TOKEN)." },
          cwd: { type: "string", description: "Where it runs; default this session's workspace." },
          timeout_seconds: { type: "integer", minimum: 1, maximum: 3600, description: "Stopped after this long; default 600." },
          station: { type: "string", description: "The station the grant was asked for (secret_use station); default that one." },
        },
        required: ["grant", "command"],
        additionalProperties: false,
      },
      run: async (key, args) => {
        const home = workspace(key);
        if (home === null) throw new Error("unknown session");
        const given = text(args, "cwd").trim();
        const seconds = typeof args.timeout_seconds === "number" && Number.isInteger(args.timeout_seconds) ? args.timeout_seconds : null;
        return secrets.run(key, {
          grant: text(args, "grant").trim(),
          command: text(args, "command"),
          cwd: given === "" ? home : joinPath(home, given),
          under: given,
          ...(text(args, "env") ? { env: text(args, "env").trim() } : {}),
          ...(text(args, "station").trim() ? { station: text(args, "station").trim() } : {}),
          ...(seconds !== null ? { timeoutMs: seconds * 1000 } : {}),
        });
      },
    },
  ];
}
