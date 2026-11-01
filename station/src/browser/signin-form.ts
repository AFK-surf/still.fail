// A site's sign-in form in a chat's tab, filled by the station itself (docs/vault.md 登录态, "Signing in from a card"):
// what of a sign-in the page asks for now (an account, a password, a code), each field given what the person's app sent
// as typing gives it (the field focused in a world of the page's own, its text put in as Chrome's input does: the
// page's scripts hear it as keys typed), and the form sent as Enter sends it, else by its button. Only while the tab
// is on the site asked for (its address as the browser has it, never what the page says), on a connection of its own
// (as a person's view is: view.ts), nothing of what is typed logged.
import type { Cdp } from "./cdp.ts";
import { ofSites } from "./signins.ts";
import { hostOf } from "./view.ts";

/// What of a sign-in a page asks for, by its visible fields; `blocked`: something only a person can do is on it (a
/// captcha's frame).
export type FormAsks = { username: boolean; password: boolean; code: boolean; blocked: boolean };

/// What the person's app gave: the account, its password, a one-time code.
export type FormValues = { username?: string; password?: string; code?: string };

export type FormField = "username" | "password" | "code";

/// Finds the page's sign-in fields (the top document and its open shadow roots), run in a world of its own: those of
/// each kind (FormField) a person could type in now, the first of each; `pick(kind)` focuses that one, its text
/// selected (so what is typed replaces it). A code's field: marked so (one-time-code), named so, or a short field of
/// digits; a code split one digit to a box is its first box.
const FINDER = `(() => {
  const visible = (el) => !!el && !el.disabled && !el.readOnly && el.getClientRects().length > 0 && getComputedStyle(el).visibility !== "hidden";
  const inputs = [];
  const walk = (root) => { for (const el of root.querySelectorAll("*")) { if (el.tagName === "INPUT") inputs.push(el); if (el.shadowRoot) walk(el.shadowRoot); } };
  walk(document);
  const words = (el) => [el.name, el.id, el.placeholder, el.getAttribute("aria-label")].filter(Boolean).join(" ");
  const typeOf = (el) => (el.type || "text").toLowerCase();
  const auto = (el) => (el.autocomplete || "").toLowerCase();
  const isCode = (el) => /^(text|tel|number|password)$/.test(typeOf(el)) && (auto(el) === "one-time-code"
    || /otp|totp|mfa|2fa|two.?factor|one.?time|verification|verify|authenticat|security.?code|^code$|[-_ ]code|code[-_ ]|pin\\b|验证码|动态码/i.test(words(el))
    || (el.inputMode === "numeric" && el.maxLength > 0 && el.maxLength <= 8 && typeOf(el) !== "password"));
  const shown = inputs.filter(visible);
  const code = shown.find(isCode);
  const password = shown.find((el) => typeOf(el) === "password" && !isCode(el));
  const username = shown.find((el) => el !== code && /^(text|email|tel)$/.test(typeOf(el)) && !isCode(el)
    && (/username|email|webauthn/.test(auto(el)) || /user|email|e-mail|login|account|identifier|账号|邮箱|手机/i.test(words(el)) || (password && el.compareDocumentPosition(password) & Node.DOCUMENT_POSITION_FOLLOWING)));
  const blocked = [...document.querySelectorAll("iframe")].some((f) => visible(f) && /recaptcha|hcaptcha|turnstile|captcha|arkoselabs|funcaptcha/i.test(f.src || ""));
  return { username, password, code, blocked };
})()`;

/// What the page asks for now.
export const LOOK_SCRIPT = `(() => { const f = ${FINDER}; return { username: !!f.username, password: !!f.password, code: !!f.code, blocked: f.blocked }; })()`;

/// Focuses the field of `kind`, its text selected; whether there is one.
export const pickScript = (kind: FormField) => `(() => { const el = ${FINDER}[${JSON.stringify(kind)}]; if (!el) return false; el.focus(); try { el.select(); } catch {} return document.activeElement === el || el.getRootNode().activeElement === el; })()`;

/// The button that sends the form the focus is in (or the page's only one): its middle, in CSS pixels; null for none.
/// A submit button of its form, else a button whose words say it (sign in, next, continue, verify, 登录, 下一步…).
export const BUTTON_SCRIPT = `(() => {
  const visible = (el) => !!el && !el.disabled && el.getClientRects().length > 0;
  const a = document.activeElement;
  const scope = (a && a.form) || document;
  const all = [...scope.querySelectorAll("button, input[type=submit], [role=button]")].filter(visible);
  const said = (el) => (el.innerText || el.value || el.getAttribute("aria-label") || "").trim();
  const b = all.find((el) => (el.type || "").toLowerCase() === "submit" && el.tagName !== "DIV")
    || all.find((el) => /^(sign in|log in|login|next|continue|verify|submit|登录|登入|下一步|继续|验证|确定)$/i.test(said(el)));
  if (!b) return null;
  const r = b.getBoundingClientRect();
  return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
})()`;

/// A tab's sign-in form, on a connection of its own to the browser.
export class TabForm {
  readonly #cdp: Cdp;
  readonly #session: string;
  readonly #targetId: string;
  #world: { frame: string; context: number } | null = null;

  constructor(cdp: Cdp, session: string, targetId: string) {
    this.#cdp = cdp;
    this.#session = session;
    this.#targetId = targetId;
  }

  /// The tab's host, as the browser has its address ("" when it is gone).
  async host(): Promise<string> {
    const { targetInfo } = await this.#cdp.send("Target.getTargetInfo", { targetId: this.#targetId }).catch(() => ({ targetInfo: null }));
    return hostOf(String(targetInfo?.url ?? ""));
  }

  /// The tab's address, as the browser has it.
  async url(): Promise<string> {
    const { targetInfo } = await this.#cdp.send("Target.getTargetInfo", { targetId: this.#targetId }).catch(() => ({ targetInfo: null }));
    return String(targetInfo?.url ?? "");
  }

  /// Whether the tab is on `site` (or a host under it).
  async on(site: string): Promise<boolean> {
    const host = await this.host();
    return host !== "" && ofSites(host, [site]);
  }

  /// Runs `expression` in the page's top frame, in a world of the station's own (made again as the page moves on).
  async #run(expression: string): Promise<any> {
    for (let tries = 0; tries < 2; tries++) {
      const { frameTree } = await this.#cdp.send("Page.getFrameTree", {}, this.#session);
      const frame = String(frameTree?.frame?.id ?? "");
      if (this.#world?.frame !== frame || tries > 0) {
        const { executionContextId } = await this.#cdp.send("Page.createIsolatedWorld", { frameId: frame, worldName: "stillfail-signin" }, this.#session);
        this.#world = { frame, context: executionContextId };
      }
      try {
        const r = await this.#cdp.send("Runtime.evaluate", { expression, contextId: this.#world!.context, returnByValue: true }, this.#session);
        if (r?.exceptionDetails === undefined) return r?.result?.value;
      } catch (e) {
        // (the page went on meanwhile: its world went with it)
        if (!/context|not found|destroyed/i.test((e as Error).message)) throw e;
      }
      this.#world = null;
    }
    return undefined;
  }

  /// What the page asks for now.
  async look(): Promise<FormAsks> {
    const v = await this.#run(LOOK_SCRIPT).catch(() => undefined);
    return { username: v?.username === true, password: v?.password === true, code: v?.code === true, blocked: v?.blocked === true };
  }

  /// `value` typed into the page's field of `kind`, as Chrome puts text in (a code a digit at a time, so a code split
  /// one to a box moves on as typed); whether there was one.
  async type(kind: FormField, value: string): Promise<boolean> {
    if ((await this.#run(pickScript(kind))) !== true) return false;
    if (kind === "code") for (const ch of value) await this.#cdp.send("Input.insertText", { text: ch }, this.#session);
    else await this.#cdp.send("Input.insertText", { text: value }, this.#session);
    return true;
  }

  /// Sends the form the focus is in: Enter, as a person presses it.
  async enter(): Promise<void> {
    for (const type of ["keyDown", "keyUp"] as const) {
      await this.#cdp.send("Input.dispatchKeyEvent", { type, key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13, ...(type === "keyDown" ? { text: "\r" } : {}) }, this.#session);
    }
  }

  /// Sends it by its button, clicked where it is; whether there was one.
  async press(): Promise<boolean> {
    const at = await this.#run(BUTTON_SCRIPT);
    if (typeof at?.x !== "number" || typeof at?.y !== "number") return false;
    for (const type of ["mousePressed", "mouseReleased"] as const) {
      await this.#cdp.send("Input.dispatchMouseEvent", { type, x: at.x, y: at.y, button: "left", clickCount: 1 }, this.#session);
    }
    return true;
  }

  /// Marks the page as it is now; `marked`: whether it is still that page (a document after it has no mark, the same
  /// address loaded again too).
  async mark(): Promise<void> {
    await this.#run("window.__stillfailSent = true");
  }

  async marked(): Promise<boolean> {
    return (await this.#run("window.__stillfailSent === true").catch(() => false)) === true;
  }

  close() {
    this.#cdp.close();
  }
}

/// How a fill went: the page left its sign-in (`left`: signed in, as far as the station can tell: the agent looks),
/// it asks for a code it was not given (`code`), or only a person can go on (`person`, and why: a captcha, the page
/// took none of it, it asks again for what was typed).
export type Driven = { state: "left" | "code" | "person"; why?: "blocked" | "refused" | "stuck" | "elsewhere" };

/// How long the page is given to move on once its form is sent, and how often it is looked at meanwhile.
export const MOVE_MS = 8000;
const LOOK_MS = 300;
/// The most steps a sign-in takes (an account, a password, a code, and one more a site may ask).
const STEPS = 5;

/// Goes through `site`'s sign-in on `form`'s tab with `values`: each step's fields typed (each of `used`, what an
/// earlier fill typed, not again: asked again, the page refused it), the form sent, until the page leaves its sign-in,
/// asks a code not given, or needs a person. `wait(ms)` waits (the station's time); what was typed is added to `used`.
export async function drive(form: TabForm, site: string, values: FormValues, used: Set<FormField>, wait: (ms: number) => Promise<void>): Promise<Driven> {
  for (let step = 0; step < STEPS; step++) {
    if (!(await form.on(site))) return step === 0 ? { state: "person", why: "elsewhere" } : { state: "left" };
    const asks = await form.look();
    if (asks.blocked) return { state: "person", why: "blocked" };
    if (!asks.username && !asks.password && !asks.code) return { state: "left" };
    const typed: FormField[] = [];
    for (const kind of ["username", "password", "code"] as const) {
      const value = values[kind];
      if (!asks[kind] || value === undefined || value === "" || used.has(kind)) continue;
      if (await form.type(kind, value)) typed.push(kind);
    }
    if (typed.length === 0) {
      if (asks.code && !used.has("code")) return { state: "code" };
      return { state: "person", why: "refused" };
    }
    for (const kind of typed) used.add(kind);
    const before = JSON.stringify({ url: await form.url(), asks });
    await form.mark();
    const moved = async () => {
      for (let t = 0; t < MOVE_MS; t += LOOK_MS) {
        await wait(LOOK_MS);
        if (!(await form.marked()) || JSON.stringify({ url: await form.url(), asks: await form.look() }) !== before) return true;
      }
      return false;
    };
    await form.enter();
    if (!(await moved()) && !((await form.press()) && (await moved()))) return { state: "person", why: "stuck" };
  }
  return { state: "person", why: "stuck" };
}
