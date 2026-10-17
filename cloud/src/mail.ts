// The sign-in codes sent to an email (login.ts), through Cloudflare Email Service: the send_email binding EMAIL
// (wrangler.jsonc), from EMAIL_FROM, whose domain is onboarded in the dashboard (Email Service › Email Sending).
import { escape } from "./page";
import { tr, type Lang } from "./i18n.ts";
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
  const body = tr(lang, "cloud.mail.code.body", { code });
  const more = [...(device ? [tr(lang, "cloud.mail.code.for", { name: device })] : []), tr(lang, "cloud.mail.code.notYou")];
  const html =
    `<div style="font:16px/1.7 system-ui;color:#242424"><p>${escape(body).replace(code, `<strong style="font-size:28px;letter-spacing:4px">${code}</strong>`)}</p>` +
    more.map((line, i) => `<p${i === more.length - 1 ? ' style="color:#777"' : ""}>${escape(line)}</p>`).join("") +
    "</div>";
  await env.EMAIL!.send({ from: { email: env.EMAIL_FROM!, name: "still.fail" }, to, subject: tr(lang, "cloud.mail.code.subject", { code }), text: [body, ...more].join("\n\n"), html });
}
