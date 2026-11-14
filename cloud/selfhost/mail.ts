// The sign-in codes' mail (EMAIL, Cloudflare Email Service's send_email on Cloudflare: src/mail.ts) of a self-hosted
// cloud: through the operator's SMTP relay (SMTP_URL: smtp://user:password@host:587, STARTTLS before anything is said,
// or smtps://…:465), or, without one, written to the log, the way test/dev.ts's MAIL=1 shows them: for a cloud that
// is only its operator's, who reads its log (README.md says when that is enough).
import { WorkerEntrypoint } from "cloudflare:workers";
import { connect } from "cloudflare:sockets";
import type { MailMessage } from "../src/mail.ts";

export type MailEnv = { SMTP_URL?: string | null; SMTP_HELO?: string | null };

/** An error as the binding's: its `code` what went wrong (as Cloudflare's E_… codes are). */
const failed = (code: string, detail = "") => Object.assign(new Error(`${code}${detail ? `: ${detail}` : ""}`), { code });

/** `text` as an RFC 2047 encoded word where it is not plain ASCII. */
export const encodedWord = (text: string) => (/^[\x20-\x7e]*$/.test(text) ? text : `=?UTF-8?B?${base64(text)}?=`);
const base64 = (text: string) => btoa(String.fromCharCode(...new TextEncoder().encode(text)));
/** base64 in lines of 76. */
const lines = (text: string) => base64(text).replace(/.{76}/g, "$&\r\n");

/** The message as SMTP's DATA carries it: text and HTML, each base64, its headers' words encoded. */
export function mime(message: MailMessage, id: string, date: Date): string {
  const from = typeof message.from === "string" ? { email: message.from } : message.from;
  const boundary = `b-${id}`;
  return [
    `From: ${from.name ? `${encodedWord(from.name.replace(/["\\]/g, ""))} ` : ""}<${from.email}>`,
    `To: <${message.to}>`,
    `Subject: ${encodedWord(message.subject)}`,
    `Date: ${date.toUTCString().replace("GMT", "+0000")}`,
    `Message-ID: <${id}@${from.email.split("@")[1]}>`,
    "MIME-Version: 1.0",
    `Content-Type: multipart/alternative; boundary="${boundary}"`,
    "",
    `--${boundary}`,
    "Content-Type: text/plain; charset=utf-8",
    "Content-Transfer-Encoding: base64",
    "",
    lines(message.text),
    `--${boundary}`,
    "Content-Type: text/html; charset=utf-8",
    "Content-Transfer-Encoding: base64",
    "",
    lines(message.html),
    `--${boundary}--`,
    "",
  ].join("\r\n");
}

/** One SMTP conversation: what the server says, a reply at a time (its last line's code). */
class Conversation {
  #reader: ReadableStreamDefaultReader<Uint8Array>;
  #writer: WritableStreamDefaultWriter<Uint8Array>;
  #buffer = "";
  constructor(socket: Socket) {
    this.#reader = socket.readable.getReader();
    this.#writer = socket.writable.getWriter();
  }
  async reply(): Promise<{ code: number; text: string }> {
    const said: string[] = [];
    for (;;) {
      const end = this.#buffer.indexOf("\r\n");
      if (end < 0) {
        const { value, done } = await this.#reader.read();
        if (done) throw failed("E_SMTP", "the server went away");
        this.#buffer += new TextDecoder().decode(value);
        continue;
      }
      const line = this.#buffer.slice(0, end);
      this.#buffer = this.#buffer.slice(end + 2);
      said.push(line);
      if (/^\d{3} /.test(line) || /^\d{3}$/.test(line)) return { code: Number(line.slice(0, 3)), text: said.join("\n") };
    }
  }
  async say(line: string, expect: number): Promise<string> {
    await this.#writer.write(new TextEncoder().encode(`${line}\r\n`));
    const { code, text } = await this.reply();
    if (Math.floor(code / 100) !== Math.floor(expect / 100)) throw failed("E_SMTP", text.replace(/^AUTH .*/, "AUTH"));
    return text;
  }
  release() {
    this.#reader.releaseLock();
    this.#writer.releaseLock();
  }
}

/** Sends `message` through the relay at `url` (smtp: STARTTLS, smtps: TLS from the start; user and password, if any, with AUTH PLAIN). */
export async function sendSmtp(url: URL, helo: string, message: MailMessage, id: string, date = new Date()): Promise<void> {
  const tls = url.protocol === "smtps:";
  if (!tls && url.protocol !== "smtp:") throw failed("E_SMTP", "SMTP_URL is smtp: or smtps:");
  let socket = connect({ hostname: url.hostname, port: Number(url.port) || (tls ? 465 : 587) }, { secureTransport: tls ? "on" : "starttls", allowHalfOpen: false });
  let talk = new Conversation(socket);
  try {
    if ((await talk.reply()).code !== 220) throw failed("E_SMTP", "no greeting");
    await talk.say(`EHLO ${helo}`, 250);
    if (!tls) {
      // Never in the clear: a relay that cannot start TLS is not used.
      await talk.say("STARTTLS", 220);
      talk.release();
      socket = socket.startTls();
      talk = new Conversation(socket);
      await talk.say(`EHLO ${helo}`, 250);
    }
    if (url.username) await talk.say(`AUTH PLAIN ${base64(`\0${decodeURIComponent(url.username)}\0${decodeURIComponent(url.password)}`)}`, 235);
    const from = typeof message.from === "string" ? message.from : message.from.email;
    await talk.say(`MAIL FROM:<${from}>`, 250);
    await talk.say(`RCPT TO:<${message.to}>`, 250);
    await talk.say("DATA", 354);
    // (a line that starts with a dot is sent with another before it)
    await talk.say(`${mime(message, id, date).replace(/^\./gm, "..")}\r\n.`, 250);
    await talk.say("QUIT", 221).catch(() => "");
  } finally {
    await socket.close().catch(() => undefined);
  }
}

export class Mail extends WorkerEntrypoint<MailEnv> {
  async send(message: MailMessage): Promise<{ messageId: string }> {
    const messageId = crypto.randomUUID();
    if (/[\r\n<>]/.test(message.to)) throw failed("E_RECIPIENT_NOT_ALLOWED");
    if (!this.env.SMTP_URL) {
      // No relay: the mail on the log (its text has the code), for the operator to read out.
      console.log(`MAIL to ${message.to}: ${message.subject}\n${message.text}`);
      return { messageId };
    }
    await sendSmtp(new URL(this.env.SMTP_URL), this.env.SMTP_HELO || "localhost", message, messageId);
    return { messageId };
  }
}

export default { fetch: () => new Response("Not found", { status: 404 }) } satisfies ExportedHandler<MailEnv>;
