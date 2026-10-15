// A story's steps taken in the page itself, for the gallery's frame (the tests take them with Playwright, which also
// moves the real pointer: what only shows under it, :hover, shows there and not here). Reads the selectors the
// stories use: CSS, `text=…` (exact, or /a regex/), `a:has-text("…")` and `outer >> inner`.
import type { Step } from "./stories.tsx";

const visible = (el: Element) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };

/** The elements whose own text is `text` (or matches /it/), innermost first. */
function byText(scope: ParentNode, text: string): Element[] {
  const re = /^\/(.*)\/$/.exec(text);
  const fits = (s: string) => (re ? new RegExp(re[1]!).test(s) : s === text);
  return [...scope.querySelectorAll("*")].filter((el) => fits((el as HTMLElement).innerText?.trim() ?? "") && ![...el.children].some((c) => fits((c as HTMLElement).innerText?.trim() ?? "")));
}

function find(selector: string, scope: ParentNode = document): Element | undefined {
  const [head, ...rest] = selector.split(" >> ");
  let found: Element[];
  const text = /^text=(.*)$/.exec(head!);
  const has = /^(.*):has-text\("(.*)"\)$/.exec(head!);
  if (text) found = byText(scope, text[1]!.replace(/^"(.*)"$/, "$1"));
  else if (has) found = [...scope.querySelectorAll(has[1]!)].filter((el) => (el as HTMLElement).innerText.includes(has[2]!));
  else found = [...scope.querySelectorAll(head!)];
  for (const el of found.filter(visible)) {
    const inner = rest.length ? find(rest.join(" >> "), el) : el;
    if (inner) return inner;
  }
  return undefined;
}

function at(el: Element): { clientX: number; clientY: number } {
  const r = el.getBoundingClientRect();
  return { clientX: r.left + r.width / 2, clientY: r.top + r.height / 2 };
}

function point(el: Element, types: string[], extra: MouseEventInit = {}) {
  const init = { bubbles: true, cancelable: true, composed: true, view: window, ...at(el), ...extra };
  for (const type of types) {
    el.dispatchEvent(type.startsWith("pointer") ? new PointerEvent(type, { ...init, pointerType: "mouse", isPrimary: true, pointerId: 1 }) : new MouseEvent(type, init));
  }
}

const settle = (ms: number) => new Promise((r) => setTimeout(r, ms));
async function waitFor(selector: string): Promise<Element> {
  for (let i = 0; i < 50; i++) { const el = find(selector); if (el) return el; await settle(100); }
  throw new Error(`no ${selector}`);
}

/** Takes `steps` as the tests do; stops at the first it cannot. */
export async function play(steps: Step[]): Promise<void> {
  await settle(1500);
  for (const step of steps) {
    if (step.click || step.text) {
      const el = await waitFor(step.click ?? `text=${step.text}`);
      point(el, ["pointerover", "pointerenter", "pointerdown", "mousedown"], { button: 0, buttons: 1 });
      if (el.matches("input, textarea, [contenteditable]")) (el as HTMLElement).focus();
      point(el, ["pointerup", "mouseup", "click"], { button: 0 });
    }
    if (step.rightClick) point(await waitFor(step.rightClick), ["pointerdown", "mousedown", "pointerup", "mouseup", "contextmenu"], { button: 2 });
    if (step.hover) point(await waitFor(step.hover), ["pointerover", "pointerenter", "pointermove", "mouseover", "mouseenter", "mousemove"]);
    if (step.move) {
      const el = document.elementFromPoint(step.move[0], step.move[1]);
      if (el) point(el, ["pointermove", "mousemove"], { clientX: step.move[0], clientY: step.move[1] });
    }
    if (step.key) {
      const parts = step.key.split("+");
      const key = parts.pop()!;
      const mac = /Mac/.test(navigator.platform);
      const meta = parts.includes("Meta") || (mac && parts.includes("ControlOrMeta"));
      const ctrl = parts.includes("Control") || (!mac && parts.includes("ControlOrMeta"));
      const init = { key, code: key.length === 1 ? `Key${key.toUpperCase()}` : key, metaKey: meta, ctrlKey: ctrl, shiftKey: parts.includes("Shift"), bubbles: true, cancelable: true };
      (document.activeElement ?? document.body).dispatchEvent(new KeyboardEvent("keydown", init));
      (document.activeElement ?? document.body).dispatchEvent(new KeyboardEvent("keyup", init));
    }
    await settle(700);
  }
}
