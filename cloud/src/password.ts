// Signing in with an email and a password, for the accounts the operator set up (REVIEW_ACCOUNTS): the one App Store
// review signs in with, which cannot go through Google. Nobody signs up this way; any other email is refused.
import { ulid } from "ulid";
import { digest, readJson, reply, type Identity } from "./auth";
import { consumeLoginRate } from "./login";
import type { Env } from "./env";

type PasswordAccount = { email: string; password: string; name?: string };

const refused = () => reply({ error: "invalid_credentials" }, 401);

/** REVIEW_ACCOUNTS, a JSON list of {email, password, name?}; a malformed one lets nobody in. */
export function passwordAccounts(env: Env): PasswordAccount[] {
  try {
    const list: unknown = JSON.parse(env.REVIEW_ACCOUNTS ?? "[]");
    if (!Array.isArray(list)) return [];
    return list.filter(
      (a): a is PasswordAccount =>
        a && typeof a.email === "string" && a.email.includes("@") && typeof a.password === "string" && a.password.length >= 12 && (a.name === undefined || typeof a.name === "string"),
    );
  } catch {
    return [];
  }
}

/** Its account: a subject of its own, never a Google one (those are digits). */
export async function passwordIdentity(account: PasswordAccount): Promise<Identity> {
  const email = account.email.trim().toLowerCase();
  return { sub: `pw-${(await digest(email)).slice(0, 32)}`, email, name: account.name ?? "", picture: "" };
}

/** POST /v1/auth/password {email, password, name}: the same tokens a Google sign-in's /v1/auth/token answers. */
export async function passwordSignIn(env: Env, request: Request): Promise<Response> {
  let body: Record<string, unknown>;
  try {
    body = await readJson(request);
  } catch {
    return reply({ error: "invalid_request" }, 400);
  }
  if (typeof body.email !== "string" || typeof body.password !== "string" || body.password.length > 256 || (body.name !== undefined && (typeof body.name !== "string" || body.name.length > 80)))
    return reply({ error: "invalid_request" }, 400);
  if (!(await consumeLoginRate(env, request))) return reply({ error: "rate_limited" }, 429, { "retry-after": "60" });
  const email = body.email.trim().toLowerCase();
  const account = passwordAccounts(env).find((a) => a.email.trim().toLowerCase() === email);
  // Digests compared, as the admin token is: the time it takes says nothing of how much of the password was right.
  if (!account || (await digest(body.password)) !== (await digest(account.password))) return refused();
  const identity = await passwordIdentity(account);
  return env.ACCOUNTS.getByName(identity.sub).create(identity, ulid(), ((body.name as string | undefined) ?? "still.fail").trim() || "still.fail");
}
