// Pieces shared by still.fail cloud's pages and the admin's console: people's
// avatars, the sign-in page and where a sign-in comes back to.
import { useEffect, useState, type ReactNode } from "react";
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
  return (
    <div className={`${shellCss.gate} ${css.signInPage}`}>
      <Illustration name="sign-in" />
      <h1>{title}</h1>
      <p>{lead ?? t("web-pages.signIn.lead")}</p>
      <Button variant="primary" busy={signIn.busy} onClick={() => void signIn.signIn()}>{t("web-pages.signIn.google")}</Button>
      <PasswordSignIn />
    </div>
  );
}

/** Signing in with an email and a password, for the accounts set up for it (App Store review's): folded away under a link. */
function PasswordSignIn() {
  const [open, setOpen] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const busy = useDoing("auth.password");
  if (!open) return <button type="button" className={css.passwordLink} onClick={() => setOpen(true)}>{t("web-pages.signIn.password")}</button>;
  return (
    <form className={css.passwordForm} onSubmit={(e) => {
      e.preventDefault();
      setError(null);
      passwordSignIn(email.trim(), password).catch((e: unknown) => setError(e instanceof Error ? e.message : String(e)));
    }}>
      <input className={controlsCss.input} type="email" autoComplete="username" autoFocus placeholder={t("web-pages.signIn.email")} aria-label={t("web-pages.signIn.email")} value={email} onChange={(e) => setEmail(e.target.value)} />
      <input className={controlsCss.input} type="password" autoComplete="current-password" placeholder={t("web-pages.signIn.passwordField")} aria-label={t("web-pages.signIn.passwordField")} value={password} onChange={(e) => setPassword(e.target.value)} />
      {error && <p className={controlsCss.fieldError} role="alert">{error}</p>}
      <Button type="submit" variant="secondary" busy={busy} disabled={!email.trim() || !password}>{t("web-pages.signIn.passwordSubmit")}</Button>
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
