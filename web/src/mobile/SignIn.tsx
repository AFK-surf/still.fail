// Signing in on a narrow screen, as the Android app has it (apps/android/…/screens/SignIn.kt).
import { useState } from "react";
import { signIn } from "../cloud/accounts.ts";
import { Illustration } from "./parts.tsx";
import * as rootCss from "./styles/root.css.ts";
import * as css from "./SignIn.css.ts";

export function MobileSignIn() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // On its way the page leaves for Google's: the button waits till then; if it cannot, it says why.
  const go = () => {
    setBusy(true); setError(null);
    signIn().catch((e: unknown) => { setBusy(false); setError(`没能打开登录：${e instanceof Error ? e.message : String(e)}`); });
  };
  return (
    <div className={`${rootCss.m} ${css.mSignIn}`}>
      <Illustration name="sign-in" width={300} />
      <h1>让 agent 一直在干活</h1>
      <p>登录后，你所在 workspace 的所有 station 和会话都会出现在这里。</p>
      <button type="button" className={css.mGoogle} disabled={busy} onClick={go}>
        <GoogleDot />{busy ? "正在打开…" : "用 Google 登录"}
      </button>
      {error && <p className={css.mSignInError} role="alert">{error}</p>}
      <small>多个账号可以都登录，随时切换 workspace。</small>
    </div>
  );
}

/** Google's "G", on white as Google asks for it on a dark button. */
function GoogleDot() {
  return (
    <span className={css.mGoogleMark} aria-hidden="true">
      <svg width="16" height="16" viewBox="0 0 48 48">
        <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z" />
        <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z" />
        <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z" />
        <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z" />
      </svg>
    </span>
  );
}
