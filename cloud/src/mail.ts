// The sign-in codes sent to an email (login.ts), and the word to someone added to a workspace (api.ts, `sendAdded`),
// through Cloudflare Email Service: the send_email binding EMAIL
// (wrangler.jsonc), from EMAIL_FROM, whose domain is onboarded in the dashboard (Email Service › Email Sending).
import { escape } from "./page";
import { cloudProduct, tr, type Lang } from "./i18n.ts";
import type { Env } from "./env";

/** An address with the name shown beside it. */
export type MailAddress = { email: string; name?: string };
/** What the binding takes (the Workers API's EmailMessageBuilder, the part of it used here). */
export type MailMessage = { from: string | MailAddress; to: string; subject: string; text: string; html: string };
/** The send_email binding. Throws an Error with a `code` (E_SENDER_NOT_VERIFIED, E_RATE_LIMIT_EXCEEDED, …) when it cannot. */
export interface Mailer {
  send(message: MailMessage): Promise<{ messageId: string }>;
}

/** Whether signing in with an email is offered: there is a binding to send with and an address to send from. */
export const mailConfigured = (env: Env) => Boolean(env.EMAIL && env.EMAIL_FROM);

/** Sends `code` to `to`, in `lang`; `device`, what is signing in when it is a device's sign-in (the name it gave), else "". */
export async function sendCode(env: Env, lang: Lang, to: string, code: string, device: string): Promise<void> {
  const lead = tr(lang, "cloud.mail.code.lead");
  const more = [...(device ? [tr(lang, "cloud.mail.code.for", { name: device })] : []), tr(lang, "cloud.mail.code.notYou")];
  // The code on a line of its own, big, to read off or copy; not in the subject, which lock screens and mail lists show.
  const html =
    `<div style="font:16px/1.7 system-ui;color:#242424"><p>${escape(lead)}</p>` +
    `<p style="margin:16px 0;font-size:32px;font-weight:700;letter-spacing:6px;font-variant-numeric:tabular-nums">${code}</p>` +
    more.map((line, i) => `<p${i === more.length - 1 ? ' style="color:#777"' : ""}>${escape(line)}</p>`).join("") +
    "</div>";
  await env.EMAIL!.send({ from: { email: env.EMAIL_FROM!, name: cloudProduct().name }, to, subject: tr(lang, "cloud.mail.code.subject"), text: [lead, code, ...more].join("\n\n"), html });
}

/**
 * Tells `to` that `inviter` added them to `workspace` (Directory `addMembers`), in `lang`: in it already (`joined`, an
 * account of that email signed in before), or once they first sign in with it. A link to this cloud's app, no token:
 * the email itself is what lets them in. The product's name is the cloud's (`tr`, client/i18n/brand.ts).
 */
export async function sendAdded(env: Env, lang: Lang, to: string, joined: boolean, inviter: string, workspace: string): Promise<void> {
  const args = { inviter, workspace, email: to };
  const lead = tr(lang, joined ? "cloud.mail.added.joined" : "cloud.mail.added.signIn", args);
  const open = tr(lang, "cloud.mail.added.open");
  const notYou = tr(lang, "cloud.mail.added.notYou");
  const link = env.PUBLIC_ORIGIN;
  // still.fail's own page look (page.ts): its text colour, a pill of the primary colour for the one thing to do.
  const html =
    `<div style="font:16px/1.7 system-ui;color:#24272b"><p>${escape(lead)}</p>` +
    `<p style="margin:20px 0"><a href="${escape(link)}" style="display:inline-block;padding:12px 20px;border-radius:999px;background:#24272b;color:#fff;font-weight:600;text-decoration:none">${escape(open)}</a></p>` +
    `<p style="color:#777">${escape(notYou)}</p></div>`;
  await env.EMAIL!.send({
    from: { email: env.EMAIL_FROM!, name: cloudProduct().name },
    to,
    subject: tr(lang, "cloud.mail.added.subject", args),
    text: [lead, `${open}: ${link}`, notYou].join("\n\n"),
    html,
  });
}
