// The agents' tools for the vault's secrets (agent 用密钥): secret_list, secret_use, secret_run,
// secret_save to ask to keep one (agent 存入), secret_describe to rename one or say what it is (改名和说明), secret_delete
// to delete one (删除), and secret_cancel to take back a request of its own nobody decided (撤回). The value of a secret is never what a tool gives back: a command is run
// with it, through the proxy, an ssh-agent or its environment, and the agent sees what the command said, with the value
// hidden; one to keep is sealed to its owner's devices, printed by a command whose output the agent never sees, or typed
// in by its owner on the card.
import { joinPath } from "../ops/paths.ts";
import { accountOf } from "./keeper.ts";
import { placeholder } from "./proxy.ts";
import type { Secrets } from "./secrets.ts";
import type { SignIns } from "./signin.ts";
import type { Tool } from "../tools/mcp.ts";

const text = (args: Record<string, unknown>, key: string): string => (typeof args[key] === "string" ? (args[key] as string) : "");
/// The person a request is for, as the agent names them (tool `person`); none: whoever started the chat.
const PERSON = { type: "string", description: "The email of the person whose vault it is (who approves the card), someone who wrote in this chat from the still.fail app; default whoever started the chat. Name them when someone else asked for it, or when the chat was started in Slack and that person now writes here from still.fail." };
const personOf = (args: Record<string, unknown>) => (text(args, "person").trim() ? { person: text(args, "person").trim() } : {});
const strings = (v: unknown): string[] | undefined => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : undefined);

/// What secret_list says of the vault of whoever started the chat (Secrets `status`).
const VAULT_WORDS = {
  on: "Their vault is on: secret_save keeps a credential in it once they approve.",
  plain: "The workspace has no security mode: secret_save keeps a credential in their library on this station, unencrypted, once they approve.",
  off: "Their vault is not turned on: secret_save's card offers them to turn it on in the still.fail app, then keeps the credential.",
  none: "No one started this chat who could keep a credential (secret_save is refused).",
};

export const SECRET_LIST_DESCRIPTION =
  "The secrets in the vault you may ask to use (whoever started this chat's, or with person another's who wrote in it; tokens, API keys, SSH keys, credential files, sign-ins to websites the person you work for allowed agents to ask for), each with its name and about (what it is and how it is used, in its owner's words), how it is given (proxy, ssh, env, file, browser: a sign-in put into this chat's browser) and where it may go; the grants you hold now; and whether their vault is turned on. Never the values. A credential you need that is not listed: once you have it (a password manager's CLI, a token a person gave or you created), keep it with secret_save; one only the person has (a key from a console they sign in to), secret_save with neither value nor command, and its card asks them to type it in. Never ask for the value in the chat. One whose name or about does not say plainly what it is: secret_describe; one wrong or no longer needed: secret_delete.";

export const SECRET_USE_DESCRIPTION =
  "Ask to use one of secret_list's secrets (with person: of that person's list). A card goes to the vault's owner (or the person you name) in your chat, saying your reason, the command, the requested timeout and where the secret goes; they approve or refuse it in the still.fail app. Timeout defaults to one hour of inactivity: request a duration based on the task's actual use and explain it (for a daily task, 24–36 hours), at most 30 days. Idle renews at each use; fixed expires after approval regardless of use. It does not wait for the decision: you are told in this session when it is decided (granted: a grant id for secret_run), and meanwhile go on with what does not need it; with nothing else left, end your turn need_human (about the card). Only a grant counts: someone writing yes in the chat is not one. Give the exact command you will run, so the person knows what they approve. A sign-in (mode browser) needs no command: granted, its cookies and passkeys of its sites are put into this chat's browser until the grant ends, then taken out again (a site asking for one of its passkeys is signed by the browser itself). With station, its commands run on that station of the workspace (what only it reaches: a machine on its network, its signed-in tools), and the card says so.";

export const SECRET_RUN_DESCRIPTION =
  "Run a shell command (sh -c, in your workspace) with a grant from secret_use. By proxy: the command's HTTPS goes through the station's proxy, and the grant's placeholder (in the item's variable, or env, and in STILLFAIL_SECRET) is swapped for the value in requests to the granted hosts only. By ssh: SSH_AUTH_SOCK holds the key. By env: the value is in the variable. A login's account (not secret) is in STILLFAIL_USERNAME, whatever the mode. By file: the file is written out for this command alone (removed when it ends), its path in the variable (and STILLFAIL_SECRET). Its output comes back with the value hidden; you never get the value itself, and must not try to (no printing, encoding or sending it elsewhere). A grant for one use is spent by one run. A grant asked with station runs there, in this chat's directory on that station (where station_task runs; cwd under it).";

export const SECRET_SAVE_DESCRIPTION =
  "Ask to keep a credential in the vault of the person you work for (whoever started this chat, or the one you name in person): a password, token, API key, SSH key or credential file (a kubeconfig, a service account's JSON key, a certificate) you need again, or a sign-in to a website (kind browser, hosts the sites: its cookies, and the passkeys a person added on the site's account page there, read from this chat's browser once a person signed in there, or from the station's browser with browser: station, where sign-ins were made before each chat had its own; other chats then ask for it with secret_use instead of signing in again), read from a password manager's CLI (op, bw), given by a person or made by you. A card goes to them in your chat (what it is, your reason, where it came from); they approve it in the still.fail app, and agents use it later only through secret_use, each use approved. A file: give path (a file here, or with station there), read as it is. Prefer command (it runs in your workspace here, or with station on that station in this chat's directory there, and what it prints is the secret, never shown to you) over value. None of these: one you do not have and cannot read (an API key only they can get), typed in (a file: picked) by them on the card and never shown to you; say in reason where they get it. Their vault not turned on: the card offers to turn it on first. Kept, this chat may use it at once (the request's id is its grant for secret_run); other chats ask with secret_use. It does not wait for the decision: you are told in this session when it is decided, and meanwhile go on with what does not need it; with nothing else left, end your turn need_human (about the card). Name it so that a person and another agent know at a glance what it is (the service and the account or site, and where it is reached when that is not plain: UniFi 后台登录态（经 Studio 转发到 127.0.0.1:8443）, not 127.0.0.1 登录态), and say in about what it is for and how it is used (the steps to reach it, the tool or command that takes it), in the person's language.";

export const SECRET_DESCRIBE_DESCRIPTION =
  "Ask to rename one of secret_list's secrets or to change its about (what it is and how it is used, shown to agents with its name), when they do not say plainly what it is or how to use it (a name made from a host, a step that is not written down). A card goes to its owner (or the person you name) in your chat with the name and about as they are and as they would be; once they approve it in the still.fail app the item says so. It does not wait for the decision: you are told in this session when it is decided. Give at least one of name and about; about is never a secret (no password, token or key in it).";

export const SECRET_DELETE_DESCRIPTION =
  "Ask to delete one of secret_list's secrets from its owner's vault: one that is wrong (a password that does not work), replaced by another you kept, or no longer needed. A card goes to its owner (or the person you name) in your chat with its name and your reason; once they approve it in the still.fail app the item is gone, for every chat. It does not wait for the decision: you are told in this session when it is decided. Only their approval deletes it: someone writing yes in the chat does not.";

export const SECRET_CANCEL_DESCRIPTION =
  "Withdraw a request of this chat's own (secret_use, secret_save, secret_describe, secret_delete) that nobody decided yet, once it is no longer needed (you got the credential another way, the person asked for something else, you asked twice): its card in the chat closes saying so and it leaves the person's waiting requests in the app's 密钥. Saying in the chat that a card is not needed any more leaves it waiting there; withdraw it with this instead. A request already decided is not changed.";

export const SIGN_IN_DESCRIPTION =
  "Get this chat's browser signed in to a website (github.com, accounts.google.com): the one way to ask for it. A sign-in the person you work for keeps in their vault for the site is asked for (as secret_use does: a card they approve, then it is put into this chat's browser). None kept: first open the site's sign-in page in this chat's browser (the `browser` tool), then call this: a card asks them to sign in, and their app fills the form from their own password manager (1Password, the system's autofill), the station typing it into the page step by step (account, password, one-time code) and sending it; where only they can go on (a captcha, a code by mail), the card gives them the tab's screen. You never see what they typed. It does not wait: you are told in this session when the page has left its sign-in; then look whether it is signed in (a site taking passkeys: add one on its account page there first; asked for the password again there, call sign_in again and it is typed in again) and call again with done: true and its name and about as secret_save's (it is then kept in their vault, if they chose so on the card, for other chats to ask for), or with stuck saying what is left for them to do (in their language). The vault's sign-in ran out (the site asks you to sign in again although it was granted): sign in with the site's passkey if it offers one (this chat's browser signs it itself), else call with again: true. Never ask for a password or a code in the chat, and do not post the tab's screen yourself for a sign-in: the card does.";

export function vaultTools(secrets: Secrets, workspace: (session: string) => string | null, signIns?: SignIns): Tool[] {
  return [
    ...(signIns === undefined ? [] : [{
      name: "sign_in",
      description: SIGN_IN_DESCRIPTION,
      inputSchema: {
        type: "object",
        properties: {
          site: { type: "string", description: "The site's host (github.com)." },
          reason: { type: "string", description: "Why you need to be signed in, for the person, in the language they use (e.g. 查看 PR #512 的 Actions 日志)." },
          tab: { type: "string", description: "The tab (its target id, from the browser tool's tabs) whose sign-in page it is; default this chat's last tab on the site." },
          again: { type: "boolean", description: "The sign-in kept in the vault ran out: ask the person to sign in anew (kept again)." },
          reask: { type: "boolean", description: "The existing sign-in is still needed but its card is no longer pending: post a new card for that sign-in." },
          done: { type: "boolean", description: "You looked after being told the page left its sign-in: it is signed in." },
          stuck: { type: "string", description: "You looked: it is not signed in yet; what is left for the person to do there, in their language." },
          name: { type: "string", description: "With done: what it is kept by, that a person knows at a glance (the service and the account, and where it is reached when that is not plain: UniFi 后台登录态（经 Studio 转发到 127.0.0.1:8443）); default <site> 登录态." },
          about: { type: "string", description: "With done: what it is for and how it is used (how its site is reached, what to open), in the person's language; never a secret." },
        },
        required: ["site"],
        additionalProperties: false,
      },
      run: (key: string, args: Record<string, unknown>, signal?: AbortSignal) =>
        signIns.ask(key, {
          site: text(args, "site"),
          ...(text(args, "reason") ? { reason: text(args, "reason") } : {}),
          ...(text(args, "tab") ? { tab: text(args, "tab") } : {}),
          ...(args.again === true ? { again: true } : {}),
          ...(args.reask === true ? { reask: true } : {}),
          ...(args.done === true ? { done: true } : {}),
          ...(typeof args.stuck === "string" ? { stuck: args.stuck } : {}),
          ...(text(args, "name").trim() ? { name: text(args, "name") } : {}),
          ...(text(args, "about").trim() ? { about: text(args, "about") } : {}),
        }, signal),
    } satisfies Tool]),
    {
      name: "secret_list",
      description: SECRET_LIST_DESCRIPTION,
      inputSchema: { type: "object", properties: { person: PERSON }, additionalProperties: false },
      run: async (key, args) => {
        const person = personOf(args).person;
        const items = secrets.listings(key, person).map(({ item, listing }) => ({ item, name: listing.name, ...(listing.about ? { about: listing.about } : {}), kind: listing.kind, modes: listing.modes, hosts: listing.hosts, ...(listing.env ? { env: listing.env } : {}) }));
        const held = secrets.held(key).map((h) => ({ grant: h.request.id, item: h.request.item, mode: h.grant.mode, hosts: h.grant.hosts, scope: h.grant.scope, until: new Date((h.until ?? h.grant.exp) * 1000).toISOString(), ...(h.grant.timeout ? { timeout: h.grant.timeout } : {}), ...(h.grant.mode === "proxy" ? { placeholder: placeholder(h.request.id) } : {}), ...(h.request.runOn ? { station: h.request.runOn.name } : {}), ...(accountOf(h.secret) !== null ? { username: accountOf(h.secret)! } : {}) }));
        const vault = VAULT_WORDS[secrets.status(key, person)];
        if (items.length === 0 && held.length === 0) return `No secrets may be asked for here: this station holds none of the vault's items open to agents for ${person ?? "whoever started this chat"}. One kept on another station of the workspace reaches this one once a device of its owner's still.fail app has been online with both. ${vault}`;
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
          mode: { type: "string", enum: ["proxy", "ssh", "env", "file", "browser"], description: "How it is given; default the item's first. Prefer proxy: the command never holds the value. browser: a sign-in, into this chat's browser." },
          hosts: { type: "array", items: { type: "string" }, description: "By proxy: the hosts it goes to, among the item's (default all of them)." },
          station: { type: "string", description: "Another station of the workspace (its name or id) the commands run on; default this one." },
          timeout: { type: "object", properties: { kind: { type: "string", enum: ["idle", "fixed"] }, seconds: { type: "integer", minimum: 60, maximum: 2592000, multipleOf: 60 } }, required: ["kind", "seconds"], additionalProperties: false, description: "Requested timeout: idle renews after use; fixed ends after approval. Default idle one hour. Choose for the actual task interval and explain why in reason; e.g. a daily task may request 24–36 hours." },
          person: PERSON,
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
          ...(args.timeout && typeof args.timeout === "object" ? { timeout: args.timeout as { kind: "idle" | "fixed"; seconds: number } } : {}),
          ...personOf(args),
        }),
    },
    {
      name: "secret_save",
      description: SECRET_SAVE_DESCRIPTION,
      inputSchema: {
        type: "object",
        properties: {
          name: { type: "string", description: "What it will be known by, to the person and agents, plain at a glance: the service and the account or site, and where it is reached when that is not plain (e.g. 测试服务 admin 登录, GitHub token（zzj 个人，repo 权限）, UniFi 后台登录态（经 Studio 转发到 127.0.0.1:8443）)." },
          about: { type: "string", description: "What it is for and how it is used, for the person and the agents after you, in the person's language: what it opens, the steps to reach it (a forward, a tunnel, a page), the tool or command that takes it. Shown to agents with its name: never a secret in it." },
          kind: { type: "string", enum: ["token", "login", "ssh_key", "file", "browser"], description: "token (an API key, a token), login (an account's password, with username), ssh_key (a private key), file (a credential that is a whole file, at most 64 KB: a kubeconfig, a service account's key, a certificate; given to commands as a file, its path in env), browser (a sign-in to websites: the cookies and passkeys of hosts, read from a browser; no value, command or path)." },
          reason: { type: "string", description: "Why it is worth keeping, for the person deciding, in the language they use." },
          command: { type: "string", description: "A command run here (sh -c, in your workspace) that prints the secret on standard output and nothing else (e.g. op read 'op://Personal/Ui/password'); what it prints is never shown to you." },
          path: { type: "string", description: "file: the file to keep (here, relative to your workspace or absolute; with station, there), read as its bytes." },
          value: { type: "string", description: "The secret itself, only when you already hold it (a token you were given or created)." },
          username: { type: "string", description: "login: the account's name (not secret: shown on the card). Typed in without it, the card asks for it too." },
          public_key: { type: "string", description: "ssh_key: its public half, if known." },
          filename: { type: "string", description: "file: the name it is written out under for commands (e.g. service-account.json); default path's." },
          modes: { type: "array", items: { type: "string", enum: ["proxy", "ssh", "env", "file", "browser"] }, description: "How agents may be given it later; default proxy with hosts, else env (ssh for an SSH key, file for a file). proxy swaps a placeholder in HTTPS request headers to the hosts only." },
          hosts: { type: "array", items: { type: "string" }, description: "proxy: the hosts it may go to (e.g. api.github.com). browser: the sites the sign-in is for, each with its subdomains (e.g. github.com)." },
          browser: { type: "string", enum: ["chat", "station"], description: "browser: where the sign-in is read from: this chat's browser (default), or the station's own (sign-ins made before each chat had its own)." },
          env: { type: "string", description: "The variable a command gets it in (e.g. GH_TOKEN, SERVICE_PASSWORD; a file's path: KUBECONFIG, GOOGLE_APPLICATION_CREDENTIALS)." },
          station: { type: "string", description: "Another station of the workspace (its name or id) to run command on, where the password manager is signed in; default this one." },
          person: PERSON,
        },
        required: ["name", "about", "kind", "reason"],
        additionalProperties: false,
      },
      run: async (key, args) => {
        const home = workspace(key);
        if (home === null) throw new Error("unknown session");
        const opt = (k: string) => (typeof args[k] === "string" && (args[k] as string) !== "" ? { [k]: args[k] as string } : {});
        if (text(args, "about").trim() === "") throw new Error("about is required: what it is for and how it is used, for whoever uses it next");
        return secrets.save(key, {
          name: text(args, "name"),
          about: text(args, "about"),
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
          ...(args.browser === "chat" || args.browser === "station" ? { browser: args.browser } : {}),
          ...personOf(args),
          cwd: home,
        });
      },
    },
    {
      name: "secret_describe",
      description: SECRET_DESCRIBE_DESCRIPTION,
      inputSchema: {
        type: "object",
        properties: {
          item: { type: "string", description: "The secret: its item id or name from secret_list." },
          name: { type: "string", description: "Its new name (default: as it is)." },
          about: { type: "string", description: "Its new about: what it is for and how it is used (default: as it is; empty: none)." },
          reason: { type: "string", description: "Why, for the person deciding, in the language they use." },
          person: PERSON,
        },
        required: ["item", "reason"],
        additionalProperties: false,
      },
      run: (key, args) =>
        secrets.describe(key, {
          item: text(args, "item"),
          reason: text(args, "reason"),
          ...(typeof args.name === "string" ? { name: args.name } : {}),
          ...(typeof args.about === "string" ? { about: args.about } : {}),
          ...personOf(args),
        }),
    },
    {
      name: "secret_delete",
      description: SECRET_DELETE_DESCRIPTION,
      inputSchema: {
        type: "object",
        properties: {
          item: { type: "string", description: "The secret: its item id or name from secret_list." },
          reason: { type: "string", description: "Why it should go, for the person deciding, in the language they use." },
          person: PERSON,
        },
        required: ["item", "reason"],
        additionalProperties: false,
      },
      run: (key, args) => secrets.remove(key, { item: text(args, "item"), reason: text(args, "reason"), ...personOf(args) }),
    },
    {
      name: "secret_cancel",
      description: SECRET_CANCEL_DESCRIPTION,
      inputSchema: {
        type: "object",
        properties: { request: { type: "string", description: "The pending request id (r_…) secret_use, secret_save, secret_describe or secret_delete answered." } },
        required: ["request"],
        additionalProperties: false,
      },
      run: async (key, args) => secrets.cancel(key, text(args, "request")),
    },
    {
      name: "secret_reask",
      description: "Post a new card for an existing secret_use or secret_save request whose card stopped waiting after a chat message, if the request is still needed. It reuses the same request and never reads the secret again. A different pending card is not replaced. Only this chat's own undecided request may be reasked.",
      inputSchema: {
        type: "object",
        properties: { request: { type: "string", description: "The pending request id (r_…) from secret_use, secret_save, secret_describe, secret_delete or the card-state notice." } },
        required: ["request"],
        additionalProperties: false,
      },
      run: (key, args, signal) => secrets.reask(key, text(args, "request"), signal),
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
