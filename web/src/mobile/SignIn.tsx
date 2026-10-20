// Signing in on a narrow screen, as the Android app has it (apps/android/…/screens/SignIn.kt).
import { useEffect, useState } from "react";
import { signIn } from "../cloud/accounts.ts";
import { Illustration } from "./parts.tsx";
import { Spinner } from "@stillfail/ui/waiting.tsx";
import * as partsCss from "./styles/parts.css.ts";
import * as rootCss from "./styles/root.css.ts";
import * as css from "./SignIn.css.ts";
import { t } from "../i18n.ts";

/** How long the button waits for the page to leave for Google's before it is a button again. */
const OPENING_MS = 10_000;

export function MobileSignIn() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // On its way the page leaves for Google's: the button waits till then; if it cannot, it says why.
  const go = () => {
    setBusy(true); setError(null);
    signIn().catch((e: unknown) => { setBusy(false); setError(t("web-mobile.signIn.failed", { error: e instanceof Error ? e.message : String(e) })); });
  };
  // Back here without having signed in (an app on the home screen opens Google's page over itself, and that was closed;
  // the browser's back), or never left: the button is a button again.
  useEffect(() => {
    if (!busy) return;
    const back = () => { if (document.visibilityState === "visible") setBusy(false); };
    const timer = setTimeout(() => setBusy(false), OPENING_MS);
    addEventListener("pageshow", back);
    document.addEventListener("visibilitychange", back);
    return () => {
      clearTimeout(timer);
      removeEventListener("pageshow", back);
      document.removeEventListener("visibilitychange", back);
    };
  }, [busy]);
  return (
    <div className={`${rootCss.m} ${css.mSignIn}`}>
      <Illustration name="sign-in" width={300} />
      <h1>{t("web-mobile.signIn.title")}</h1>
      <p>{t("web-mobile.signIn.text")}</p>
      <button type="button" className={css.mGoogle} disabled={busy} onClick={go}>
        {busy && <Spinner className={partsCss.mSpinOnColor} />}{busy ? t("common.opening") : t("web-mobile.signIn.google")}
      </button>
      {error && <p className={css.mSignInError} role="alert">{error}</p>}
      <small>{t("web-mobile.signIn.many")}</small>
    </div>
  );
}

