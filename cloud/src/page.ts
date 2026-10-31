import type { Lang } from "./i18n.ts";
import { SIGN_IN_ILLUSTRATION } from "./illus.ts";

export function escape(value: string) {
  return value.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}
/** The pages' look: the app's (mbui's light and dark palettes: the warm paper, white fields on it, its ink as the
 * one solid button), the sign-in picture over the title as on the app's sign-in page, the system's theme. */
const STYLE = [
  ":root{color-scheme:light dark;--bg:#f5f3ef;--text:#24272b;--muted:#535559;--field:#fff;--edge:#dcd8d0;--edge-hover:#b9b4aa;--chip:#e8e4dc;--chip-hover:#ddd8ce;--primary:#24272b;--primary-hover:#41464c;--on-primary:#fff;--red:#991302}",
  "@media(prefers-color-scheme:dark){:root{--bg:#1b1c1f;--text:#ececed;--muted:#b8bbc1;--field:#26272b;--edge:#3a3b40;--edge-hover:#55575d;--chip:#313237;--chip-hover:#3a3b41;--primary:#eceded;--primary-hover:#d3d4d6;--on-primary:#1f2023;--red:#fe9d8c}}",
  'body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 -apple-system,system-ui,"PingFang SC","Hiragino Sans GB",sans-serif}',
  "main{box-sizing:border-box;max-width:380px;margin:0 auto;padding:10vh 30px 40px;text-align:center}",
  "main>svg{display:block;width:240px;max-width:100%;height:auto;margin:0 auto 16px}",
  "h1{margin:0;font-size:22px;line-height:1.3;font-weight:700}",
  "p{margin:12px 0;color:var(--muted)}",
  "strong{color:var(--text);font-weight:600}",
  "form{display:flex;flex-direction:column;gap:12px;margin:24px 0 0}",
  "button,a.button{box-sizing:border-box;display:inline-flex;align-items:center;justify-content:center;gap:10px;height:48px;padding:0 20px;border:0;border-radius:999px;background:var(--primary);color:var(--on-primary);font:inherit;font-weight:600;text-decoration:none;cursor:pointer;transition:background .15s}",
  "button:hover,a.button:hover{background:var(--primary-hover)}",
  "button.secondary{background:var(--chip);color:var(--text)}",
  "button.secondary:hover{background:var(--chip-hover)}",
  "button svg{flex:none}",
  "input{box-sizing:border-box;width:100%;height:48px;margin:0;padding:0 20px;border:1px solid var(--edge);border-radius:999px;background:var(--field);color:inherit;font:inherit;outline:none;transition:border-color .15s}",
  "input:hover,input:focus{border-color:var(--edge-hover)}",
  "input::placeholder{color:var(--muted)}",
  "input.code{font-size:22px;font-variant-numeric:tabular-nums;letter-spacing:8px;text-indent:8px;text-align:center}",
  "input.code:placeholder-shown{text-indent:0}",
  "input.code::placeholder{font-size:15px;letter-spacing:0}",
  ".or{margin:20px 0 -8px;font-size:13px}",
  ".error{color:var(--red);font-size:13px}",
  ".links{display:flex;justify-content:center;gap:4px;margin:16px 0 0}",
  "button.link{height:36px;padding:0 14px;background:none;color:var(--text);font-size:13px;font-weight:500}",
  "button.link:hover{background:var(--chip)}",
  ".legal{margin:24px 0 0;font-size:12px}",
  ".legal a{color:var(--text)}",
].join("");

// A self POST needs a non-null Origin; only same-origin requests receive the
// referrer. Chromium also applies form-action to the subsequent Google redirect,
// and to where a form's answer sends the browser back (`returnTo`: the app's
// scheme, a loopback listener's origin), which is blocked unless it is listed.
export function devicePage(lang: Lang, title: string, content: string, cookies?: string, returnTo?: string): Response {
  return new Response(
    `<!doctype html><html lang="${lang === "zh" ? "zh-CN" : "en"}"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escape(title)} · still.fail</title><style>${STYLE}</style><main>${SIGN_IN_ILLUSTRATION}<h1>${escape(title)}</h1>${content}</main></html>`,
    {
      headers: {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
        "referrer-policy": "same-origin",
        "content-security-policy": `default-src 'none'; style-src 'unsafe-inline'; form-action 'self' https://accounts.google.com${returnTo ? ` ${returnTo}` : ""}; frame-ancestors 'none'`,
        ...(cookies ? { "set-cookie": cookies } : {}),
      },
    },
  );
}
