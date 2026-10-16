// What the station knows of the services its agents log in to (docs/remote-login.md, 服务描述): how to tell whether
// the machine is logged in, and the login command to run. Only so the station page can show 已登录 / 没登录 and offer a
// login at a tap: any command can be run as a login all the same, and an agent can describe a tool of its own (kept in
// <data>/logins/services/<id>.json, which wins over a built-in one of the same id). Commands and flags as the CLIs
// were seen to behave (the experiment in the doc): a device code where a tool has both.

export type Flow = "device" | "loopback" | "open" | "terminal";

/// A prompt answered for the person (`match` a regular expression on the line the cursor is on): `text` typed, then
/// Enter (an empty `text`: Enter alone, the tool's default).
export type Answer = { match: string; text: string };

export type Description = {
  id: string;
  name: string;
  /// Found on the station's PATH: installed.
  bin: string;
  status: {
    command: string[];
    /// Logged in: exit 0, and/or the output matching.
    in: { exit?: number; match?: string };
    /// The account, from the output (its first group).
    account?: string;
  };
  login: {
    command: string[];
    /// What it is expected to ask of a person; what it does is read as it runs.
    flow: Flow;
    /// Enter pressed for the person at "Press Enter to open … in your browser".
    enter?: boolean;
    /// The device code's pattern.
    code?: string;
    /// Prompts answered for the person.
    answers?: Answer[];
  };
  logout?: string[];
  /// Words in a failed command's output that say it is not logged in (for agents: then log in).
  signedOut?: string[];
  env?: Record<string, string>;
  /// The host its login pages are expected on (a page elsewhere is pointed out).
  domains?: string[];
};

export const BUILTIN: Description[] = [
  {
    id: "gh",
    name: "GitHub",
    bin: "gh",
    status: { command: ["gh", "auth", "status", "--hostname", "github.com"], in: { exit: 0 }, account: "account (\\S+)" },
    login: {
      command: ["gh", "auth", "login", "--hostname", "github.com", "--web", "--git-protocol", "https"],
      flow: "device",
      enter: true,
      code: "\\b([A-Z0-9]{4}-[A-Z0-9]{4})\\b",
      // gh's own default (Yes): git over https uses this login.
      answers: [{ match: "Authenticate Git with your GitHub credentials", text: "" }],
    },
    logout: ["gh", "auth", "logout", "--hostname", "github.com"],
    signedOut: ["not logged into any GitHub hosts", "gh auth login", "HTTP 401", "Bad credentials"],
    domains: ["github.com"],
  },
  {
    id: "gcloud",
    name: "Google Cloud",
    bin: "gcloud",
    status: { command: ["gcloud", "auth", "list", "--filter=status:ACTIVE", "--format=value(account)"], in: { exit: 0, match: "\\S+@\\S+" }, account: "(\\S+@\\S+)" },
    login: { command: ["gcloud", "auth", "login"], flow: "loopback" },
    logout: ["gcloud", "auth", "revoke", "--all"],
    signedOut: ["You do not currently have an active account selected", "gcloud auth login", "Reauthentication required"],
    domains: ["accounts.google.com"],
  },
  {
    id: "gcloud-adc",
    name: "Google Cloud（应用默认凭据）",
    bin: "gcloud",
    status: { command: ["gcloud", "auth", "application-default", "print-access-token"], in: { exit: 0 } },
    login: { command: ["gcloud", "auth", "application-default", "login"], flow: "loopback" },
    logout: ["gcloud", "auth", "application-default", "revoke"],
    signedOut: ["Could not automatically determine credentials", "gcloud auth application-default login"],
    domains: ["accounts.google.com"],
  },
  {
    id: "npm",
    name: "npm",
    bin: "npm",
    status: { command: ["npm", "whoami"], in: { exit: 0 }, account: "^(\\S+)\\s*$" },
    login: { command: ["npm", "login", "--auth-type=web"], flow: "open", enter: true },
    logout: ["npm", "logout"],
    signedOut: ["ENEEDAUTH", "E401", "This command requires you to be logged in", "need auth"],
    domains: ["www.npmjs.com"],
  },
  {
    id: "docker",
    name: "Docker Hub",
    bin: "docker",
    status: { command: ["/bin/sh", "-c", "docker info 2>/dev/null | sed -n 's/^ *Username: *//p'"], in: { exit: 0, match: "\\S" }, account: "(\\S+)" },
    login: { command: ["docker", "login"], flow: "device", enter: true, code: "\\b([A-Z0-9]{4}-[A-Z0-9]{4})\\b" },
    logout: ["docker", "logout"],
    signedOut: ["unauthorized: authentication required", "denied: requested access to the resource is denied", "docker login"],
    domains: ["login.docker.com"],
  },
  {
    id: "aws",
    name: "AWS（SSO）",
    bin: "aws",
    status: { command: ["aws", "sts", "get-caller-identity"], in: { exit: 0 }, account: "\"Arn\":\\s*\"([^\"]+)\"" },
    login: { command: ["aws", "sso", "login", "--use-device-code"], flow: "device" },
    logout: ["aws", "sso", "logout"],
    signedOut: ["Token has expired", "Unable to locate credentials", "aws sso login", "ExpiredToken"],
  },
  {
    id: "az",
    name: "Azure",
    bin: "az",
    status: { command: ["az", "account", "show", "--query", "user.name", "--output", "tsv"], in: { exit: 0 }, account: "(\\S+)" },
    login: {
      command: ["az", "login", "--use-device-code"],
      flow: "device",
      code: "enter the code ([A-Z0-9]{8,10})",
      // The subscription it picks itself (Enter: no change).
      answers: [{ match: "Type a number or Enter", text: "" }],
    },
    logout: ["az", "logout"],
    signedOut: ["Please run 'az login'", "az login"],
    domains: ["login.microsoft.com", "microsoft.com"],
  },
  {
    id: "vercel",
    name: "Vercel",
    bin: "vercel",
    status: { command: ["vercel", "whoami"], in: { exit: 0 }, account: "(\\S+)\\s*$" },
    login: { command: ["vercel", "login"], flow: "device", code: "user_code=([A-Z0-9]{4}-[A-Z0-9]{4})" },
    logout: ["vercel", "logout"],
    signedOut: ["vercel login", "The specified token is not valid", "No existing credentials found"],
    domains: ["vercel.com"],
  },
  {
    id: "wrangler",
    name: "Cloudflare",
    bin: "wrangler",
    status: { command: ["wrangler", "whoami"], in: { exit: 0, match: "associated with the email" }, account: "email (\\S+@[^\\s.]+\\.\\S+?)\\.?\\s" },
    login: { command: ["wrangler", "login", "--device"], flow: "device", code: "\\b([A-Z0-9]{4}-?[A-Z0-9]{4})\\b" },
    logout: ["wrangler", "logout"],
    signedOut: ["wrangler login", "You are not authenticated", "Not logged in"],
    domains: ["dash.cloudflare.com", "cloudflare.com"],
  },
  {
    id: "firebase",
    name: "Firebase",
    bin: "firebase",
    status: { command: ["firebase", "login:list"], in: { exit: 0, match: "Logged in as" }, account: "Logged in as (\\S+)" },
    login: { command: ["firebase", "login"], flow: "loopback" },
    logout: ["firebase", "logout"],
    signedOut: ["firebase login", "Failed to authenticate"],
    domains: ["accounts.google.com"],
  },
  {
    id: "fly",
    name: "Fly.io",
    bin: "fly",
    status: { command: ["fly", "auth", "whoami"], in: { exit: 0 }, account: "(\\S+@\\S+)" },
    login: { command: ["fly", "auth", "login"], flow: "open" },
    logout: ["fly", "auth", "logout"],
    signedOut: ["fly auth login", "no access token available"],
    domains: ["fly.io"],
  },
  {
    id: "huggingface",
    name: "Hugging Face",
    bin: "hf",
    status: { command: ["hf", "auth", "whoami"], in: { exit: 0 }, account: "^(?:user:\\s*)?(\\S+)" },
    login: { command: ["hf", "auth", "login"], flow: "terminal" },
    logout: ["hf", "auth", "logout"],
    signedOut: ["hf auth login", "Not logged in", "401 Client Error"],
    domains: ["huggingface.co"],
  },
];

/// A description as given (an agent's, or read from its file): checked, with what it lacks said; the description.
export function checked(given: unknown): Description {
  const v = given as Record<string, any>;
  const words = (x: unknown) => Array.isArray(x) && x.length > 0 && x.every((w) => typeof w === "string" && w !== "");
  const regex = (x: unknown, what: string) => {
    if (x === undefined) return;
    if (typeof x !== "string") throw new Error(`${what} must be a regular expression (a string)`);
    try {
      new RegExp(x);
    } catch (e) {
      throw new Error(`${what}: ${(e as Error).message}`);
    }
  };
  if (v === null || typeof v !== "object" || Array.isArray(v)) throw new Error("a service description is an object (see the login tool's description)");
  if (typeof v.id !== "string" || !/^[a-z0-9][a-z0-9_-]{0,39}$/.test(v.id)) throw new Error("id: lower-case letters, digits, - and _ (at most 40), e.g. gh");
  if (typeof v.name !== "string" || v.name.trim() === "" || [...v.name].length > 60) throw new Error("name: what people call the service (at most 60 characters)");
  if (typeof v.bin !== "string" || v.bin === "" || /[\s/\\]/.test(v.bin)) throw new Error("bin: the command's name as found on PATH (e.g. gh)");
  if (!v.status || !words(v.status.command)) throw new Error("status.command: the command that says whether it is logged in, as words (e.g. [\"gh\", \"auth\", \"status\"])");
  const inn = v.status.in ?? { exit: 0 };
  if (inn.exit !== undefined && !Number.isInteger(inn.exit)) throw new Error("status.in.exit: the exit code when logged in");
  regex(inn.match, "status.in.match");
  regex(v.status.account, "status.account");
  if (!v.login || !words(v.login.command)) throw new Error("login.command: the login command, as words");
  const flow = v.login.flow ?? "terminal";
  if (!["device", "loopback", "open", "terminal"].includes(flow)) throw new Error("login.flow: device, loopback, open or terminal");
  regex(v.login.code, "login.code");
  const answers = v.login.answers ?? [];
  if (!Array.isArray(answers) || answers.some((a: any) => typeof a?.match !== "string" || typeof (a.text ?? "") !== "string")) throw new Error("login.answers: [{match, text}]");
  for (const a of answers) regex(a.match, "login.answers[].match");
  if (v.logout !== undefined && !words(v.logout)) throw new Error("logout: the logout command, as words");
  if (v.signedOut !== undefined && !(Array.isArray(v.signedOut) && v.signedOut.every((s: unknown) => typeof s === "string"))) throw new Error("signedOut: words in a failed command's output");
  if (v.env !== undefined && !(v.env && typeof v.env === "object" && Object.values(v.env).every((s) => typeof s === "string"))) throw new Error("env: {NAME: value}");
  return {
    id: v.id,
    name: v.name.trim(),
    bin: v.bin,
    status: { command: v.status.command, in: { ...(inn.exit !== undefined ? { exit: inn.exit } : {}), ...(inn.match !== undefined ? { match: inn.match } : {}) }, ...(v.status.account ? { account: v.status.account } : {}) },
    login: {
      command: v.login.command,
      flow,
      ...(v.login.enter === true ? { enter: true } : {}),
      ...(v.login.code ? { code: v.login.code } : {}),
      ...(answers.length > 0 ? { answers: answers.map((a: any) => ({ match: a.match, text: a.text ?? "" })) } : {}),
    },
    ...(v.logout ? { logout: v.logout } : {}),
    ...(v.signedOut ? { signedOut: v.signedOut } : {}),
    ...(v.env ? { env: v.env } : {}),
    ...(Array.isArray(v.domains) ? { domains: v.domains.filter((d: unknown) => typeof d === "string") } : {}),
  };
}
