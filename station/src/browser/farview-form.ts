// A chat's Farview tab's sign-in form, filled by the station ( 登录态, "Signing in from a card"), as signin-form.ts
// fills a Chrome tab's: the same finder picks the fields, each marked for the step that types into it (Farview's own
// typing: the page hears it as keys), the form sent with Enter, else by its button clicked. Over the tab's agent port
// (farview-agent.ts), so what is typed is on no command line and in no log.
import { askTab, evalIn } from "./farview-agent.ts";
import { FINDER, type FormAsks, type FormField, LOOK_SCRIPT, type SignInForm } from "./signin-form.ts";
import { ofSites } from "./signins.ts";
import { hostOf } from "./view.ts";

const MARK = "data-stillfail-signin";

/// Marks the field of `kind` (and only it); whether there is one.
const markScript = (kind: FormField) =>
  `(() => { for (const el of document.querySelectorAll("[${MARK}]")) el.removeAttribute("${MARK}"); const el = ${FINDER}[${JSON.stringify(kind)}]; if (!el) return false; el.setAttribute("${MARK}", ""); return true; })()`;

/// Marks the button that sends the form (signin-form.ts BUTTON_SCRIPT's choice); whether there is one.
const BUTTON_MARK = `(() => {
  for (const el of document.querySelectorAll("[${MARK}-button]")) el.removeAttribute("${MARK}-button");
  const visible = (el) => !!el && !el.disabled && el.getClientRects().length > 0;
  const a = document.querySelector("[${MARK}]") || document.activeElement;
  const scope = (a && a.form) || document;
  const all = [...scope.querySelectorAll("button, input[type=submit], [role=button]")].filter(visible);
  const said = (el) => (el.innerText || el.value || el.getAttribute("aria-label") || "").trim();
  const b = all.find((el) => (el.type || "").toLowerCase() === "submit" && el.tagName !== "DIV")
    || all.find((el) => /^(sign in|log in|login|next|continue|verify|submit|登录|登入|下一步|继续|验证|确定)$/i.test(said(el)));
  if (!b) return false;
  b.setAttribute("${MARK}-button", "");
  return true;
})()`;

export class FarviewForm implements SignInForm {
  readonly #port: number;

  constructor(port: number) {
    this.#port = port;
  }

  async url(): Promise<string> {
    const a = await askTab(this.#port, { kind: "look" }).catch(() => null);
    return a?.kind === "seen" ? a.url : "";
  }

  async host(): Promise<string> {
    return hostOf(await this.url());
  }

  async on(site: string): Promise<boolean> {
    const host = await this.host();
    return host !== "" && ofSites(host, [site]);
  }

  async look(): Promise<FormAsks> {
    const v = await evalIn(this.#port, LOOK_SCRIPT).catch(() => undefined);
    return { username: v?.username === true, password: v?.password === true, code: v?.code === true, blocked: v?.blocked === true };
  }

  async type(kind: FormField, value: string): Promise<boolean> {
    if ((await evalIn(this.#port, markScript(kind))) !== true) return false;
    const a = await askTab(this.#port, { kind: "act", verb: "type", selector: `[${MARK}]`, text: value });
    return a.kind === "seen";
  }

  async enter(): Promise<void> {
    await askTab(this.#port, { kind: "act", verb: "key", selector: `[${MARK}]`, text: "Enter" });
  }

  async press(): Promise<boolean> {
    if ((await evalIn(this.#port, BUTTON_MARK)) !== true) return false;
    return (await askTab(this.#port, { kind: "act", verb: "click", selector: `[${MARK}-button]`, text: "" })).kind === "seen";
  }

  async mark(): Promise<void> {
    await evalIn(this.#port, "(window.__stillfailSent = true)");
  }

  async marked(): Promise<boolean> {
    return (await evalIn(this.#port, "window.__stillfailSent === true").catch(() => false)) === true;
  }

  close() {}
}
