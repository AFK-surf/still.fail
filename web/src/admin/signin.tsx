// The admin's console's own sign-in page (/login on its host), without the core as the web's is (login/): what it is,
// then 登录或注册 on to still.fail cloud's sign-in, or an email and a password (the accounts the cloud set up for it).
import { useState } from "preact/hooks";
import { t } from "@stillfail/ui/i18n.ts";
import { Key } from "@stillfail/ui/icons.tsx";
import { NAME } from "../channel.ts";
import { Button, name, Page, start } from "../login/Login.tsx";
import { password, returnTo, SignInError } from "../login/signin.ts";
import * as css from "../login/login.css.ts";
import * as own from "./signin.css.ts";

export function AdminSignIn() {
  const to = returnTo(location.search);
  const [error, setError] = useState<string | null>(null);
  const [withPassword, setWithPassword] = useState(false);
  return (
    <Page title={t("web-login.adminTitle", { name: NAME })} lead={error ?? t("web-login.adminLead", { name: NAME })}>
      <div className={own.ways}>
        <Button primary={!withPassword} onClick={() => { setError(null); start(to).catch((e: unknown) => setError(t("web-login.unreachable", { name: NAME, error: String(e) }))); }}>{t("web-login.start")}</Button>
        <span className={own.or}>{t("web-login.or")}</span>
        {withPassword ? <PasswordSignIn to={to} /> : <button type="button" className={`${css.button} ${own.ghost}`} onClick={() => setWithPassword(true)}><Key size={16} />{t("web-login.password")}</button>}
      </div>
    </Page>
  );
}

function PasswordSignIn({ to }: { to: string }) {
  const [email, setEmail] = useState("");
  const [secret, setSecret] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  return (
    <form className={own.form} onSubmit={(e) => {
      e.preventDefault();
      setError(null);
      setBusy(true);
      password(email.trim(), secret, name()).then(() => location.replace(to), (e: unknown) => {
        setBusy(false);
        setError(e instanceof SignInError ? t(e.key === "wrongPassword" ? "web-login.wrongPassword" : `web-login.${e.key}`) : t("web-login.unreachable", { name: NAME, error: String(e) }));
      });
    }}>
      <div className={own.fields}>
        <input className={own.input} type="email" autoComplete="username" autoFocus placeholder={t("web-login.email")} aria-label={t("web-login.email")} value={email} onInput={(e) => setEmail(e.currentTarget.value)} />
        <input className={own.input} type="password" autoComplete="current-password" placeholder={t("web-login.passwordField")} aria-label={t("web-login.passwordField")} value={secret} onInput={(e) => setSecret(e.currentTarget.value)} />
      </div>
      {error && <div className={own.error} role="alert">{error}</div>}
      <button type="submit" className={`${css.button} ${css.primary}`} aria-busy={busy || undefined} disabled={busy || !email.trim() || !secret}>{t("web-login.passwordSubmit")}</button>
    </form>
  );
}
