// Pieces shared by still.fail cloud's pages and the admin's console: people's
// avatars, the sign-in page and where a sign-in comes back to.
import { useEffect, useState, type ReactNode } from "react";
import { Key } from "../icons.tsx";
import { Button } from "../ui.tsx";
import { completeSignIn, passwordSignIn, useSignIn } from "./accounts.ts";
import { useDoing } from "../doing.ts";
import * as controlsCss from "../styles/controls.css.ts";
import { Illustration } from "../brand.tsx";
import * as cloudCss from "../styles/cloud.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./gate.css.ts";
import { NAME } from "./beta.tsx";
import { t } from "../i18n.ts";

export function Avatar({ account, size = 24 }: { account: { name: string; email: string; picture: string }; size?: number }) {
  const letter = ([...(account.name || account.email)][0] ?? "?").toUpperCase();
  const [broken, setBroken] = useState(false);
  return account.picture && !broken
    ? <img className={cloudCss.person} src={account.picture} alt="" width={size} height={size} referrerPolicy="no-referrer" onError={() => setBroken(true)} />
    : <span className={`${cloudCss.person} ${cloudCss.personLetter}`} style={{ width: size, height: size, fontSize: size * .45 }} aria-hidden="true">{letter}</span>;
}

export function SignInPage({ title = t("web-pages.signIn.title", { name: NAME }), lead }: { title?: string; lead?: ReactNode }) {
  const signIn = useSignIn();
  // Signing in with a password (App Store review's account), folded away until asked for: then it is the main way.
  const [password, setPassword] = useState(false);
  return (
    <div className={`${shellCss.gate} ${css.signInPage}`}>
      <Illustration name="sign-in" />
      <h1>{title}</h1>
      <p>{lead ?? t("web-pages.signIn.lead")}</p>
      <div className={css.ways}>
        <Button variant={password ? "secondary" : "primary"} busy={signIn.busy} onClick={() => void signIn.signIn()}>
          {!signIn.busy && <GoogleMark />}{t("web-pages.signIn.google")}
        </Button>
        <span className={css.or}>{t("web-pages.signIn.or")}</span>
        {password ? <PasswordSignIn /> : <Button variant="ghost" icon={Key} onClick={() => setPassword(true)}>{t("web-pages.signIn.password")}</Button>}
      </div>
    </div>
  );
}

/** Google's "G", in its colours (as its sign-in buttons show it). */
function GoogleMark() {
  return (
    <svg width="16" height="16" viewBox="0 0 48 48" aria-hidden="true">
      <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z" />
      <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z" />
      <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z" />
      <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z" />
    </svg>
  );
}

/** Signing in with an email and a password, for the accounts set up for it (App Store review's). */
function PasswordSignIn() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const busy = useDoing("auth.password");
  return (
    <form className={css.passwordForm} onSubmit={(e) => {
      e.preventDefault();
      setError(null);
      passwordSignIn(email.trim(), password).catch((e: unknown) => setError(e instanceof Error ? e.message : String(e)));
    }}>
      <input className={controlsCss.input} type="email" autoComplete="username" autoFocus placeholder={t("web-pages.signIn.email")} aria-label={t("web-pages.signIn.email")} value={email} onChange={(e) => setEmail(e.target.value)} />
      <input className={controlsCss.input} type="password" autoComplete="current-password" placeholder={t("web-pages.signIn.passwordField")} aria-label={t("web-pages.signIn.passwordField")} value={password} onChange={(e) => setPassword(e.target.value)} />
      {error && <div className={`${controlsCss.fieldError} ${css.passwordError}`} role="alert">{error}</div>}
      <Button type="submit" variant="primary" busy={busy} disabled={!email.trim() || !password}>{t("web-pages.signIn.passwordSubmit")}</Button>
    </form>
  );
}

/** /auth/callback: finishes the sign-in, then goes where it started. */
export function Callback() {
  const [error, setError] = useState<string | null>(null);
  const signIn = useSignIn();
  useEffect(() => {
    completeSignIn().then((next) => location.replace(next), (e: Error) => setError(e.message));
  }, []);
  return (
    <div className={shellCss.gate}>
      <Illustration name="sign-in" />
      <h1>{error ? t("web-pages.signIn.failed") : t("web-pages.signIn.signingIn")}</h1>
      {error && <><p>{error}</p><Button variant="primary" busy={signIn.busy} onClick={() => void signIn.signIn("/")}>{t("web-pages.signIn.again")}</Button></>}
    </div>
  );
}
