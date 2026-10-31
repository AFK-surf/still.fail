import type { Lang } from "./i18n.ts";

export function escape(value: string) {
  return value.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}
// A self POST needs a non-null Origin; only same-origin requests receive the
// referrer. Chromium also applies form-action to the subsequent Google redirect,
// and to where a form's answer sends the browser back (`returnTo`: the app's
// scheme, a loopback listener's origin), which is blocked unless it is listed.
export function devicePage(lang: Lang, title: string, content: string, cookies?: string, returnTo?: string): Response {
  return new Response(
    `<!doctype html><html lang="${lang === "zh" ? "zh-CN" : "en"}"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escape(title)} · still.fail</title><style>body{margin:0;background:#fff;color:#24272b;font:14px/1.55 -apple-system,system-ui,"PingFang SC","Hiragino Sans GB",sans-serif}main{box-sizing:border-box;max-width:364px;margin:15vh auto;padding:32px;text-align:center}main>p:first-child{margin:0 0 8px;color:#73787d;font-size:13px}h1{margin:0;font-size:16px;font-weight:700}p{margin:12px 0;color:#646970}strong{color:#24272b;font-weight:600}form{display:flex;flex-direction:column;gap:12px;margin:20px 0 0}button{box-sizing:border-box;height:36px;padding:0 16px;border:1px solid #24272b;border-radius:999px;background:#24272b;color:#fff;font:inherit;font-size:13px;font-weight:500;cursor:pointer}button:hover{background:#3b3f45;border-color:#3b3f45}button.secondary{border-color:#c4c7cb;background:#fff;color:#24272b}button.secondary:hover{background:#f4f4f5}input{box-sizing:border-box;width:100%;height:44px;margin:0;padding:0 18px;border:0;border-radius:16px;background:rgba(36,39,43,.05);color:inherit;font:inherit;outline:none;transition:background .15s}input:hover,input:focus{background:rgba(36,39,43,.08)}input::placeholder{color:#73787d}input.code{font-size:22px;font-variant-numeric:tabular-nums;letter-spacing:8px;text-indent:8px;text-align:center}input.code:placeholder-shown{text-indent:0}input.code::placeholder{font-size:14px;letter-spacing:0}.or{margin:16px 0 -4px;color:#73787d;font-size:12px;line-height:16px}.error{color:#a12f35;font-size:13px}.links{display:flex;justify-content:center;gap:4px;margin:12px 0 0}button.link{border-color:transparent;background:none;color:#24272b}button.link:hover{background:rgba(36,39,43,.05)}a.button{display:inline-flex;align-items:center;height:36px;padding:0 16px;border-radius:999px;background:#24272b;color:#fff;font-size:13px;font-weight:500;text-decoration:none}a.button:hover{background:#3b3f45}.legal{margin:24px 0 0;color:#73787d;font-size:12px}.legal a{color:#24272b}</style><main><p>still.fail</p><h1>${escape(title)}</h1>${content}</main></html>`,
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
