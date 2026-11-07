// The sign-in pages, without the core (signin.ts): /login goes straight to still.fail cloud's sign-in, which offers
// every way to sign in; /auth/callback finishes it and goes back where it began. Taking far longer than it does, the
// callback says so and offers to load the page again or to start over: an app on the home screen has no reload of its
// own, and was stuck at 正在登录… for good (2026-10-09).
import { useEffect, useState } from "preact/hooks";
import { t } from "@stillfail/ui/i18n.ts";
import { NAME } from "../channel.ts";
import { begin, complete, deviceName, returnTo, SignInError } from "./signin.ts";
import * as css from "./login.css.ts";

/** How long the sign-in's last step may take before the page offers a way out: it takes a second or two. */
const SIGNING_IN_MS = 8000;

const name = () => deviceName((browser, os) => t("web-login.device", { brand: NAME, browser: browser || t("web-login.browser"), more: os ? ` · ${os}` : "" }));

const start = (to: string) => begin(to, name());

function Page({ title, lead, children }: { title: string; lead?: string | undefined; children?: preact.ComponentChildren }) {
  return (
    <main className={css.page}>
      <img className={css.illus} src="/illus-sign-in.svg" alt="" width={360} height={200} />
      <h1 className={css.title}>{title}</h1>
      {lead && <p className={css.lead}>{lead}</p>}
      {children && <div className={css.actions}>{children}</div>}
    </main>
  );
}

function Button({ primary = false, onClick, children }: { primary?: boolean; onClick(): void; children: string }) {
  return <button type="button" className={`${css.button}${primary ? ` ${css.primary}` : ""}`} onClick={onClick}>{children}</button>;
}

/** /login: on to still.fail cloud's sign-in at once; should that fail, a way to try again. */
export function SignIn() {
  const [error, setError] = useState<string | null>(null);
  const to = returnTo(location.search);
  useEffect(() => { start(to).catch((e: unknown) => setError(String(e))); }, []);
  if (error === null) return <Page title={t("web-login.title", { name: NAME })} lead={t("web-login.lead")} />;
  return (
    <Page title={t("web-login.title", { name: NAME })} lead={t("web-login.unreachable", { name: NAME, error })}>
      <Button primary onClick={() => { setError(null); start(to).catch((e: unknown) => setError(String(e))); }}>{t("web-login.start")}</Button>
    </Page>
  );
}

/** /auth/callback: the sign-in finished, then where it began. */
export function Callback() {
  const [error, setError] = useState<string | null>(null);
  const [slow, setSlow] = useState(false);
  useEffect(() => {
    const timer = setTimeout(() => setSlow(true), SIGNING_IN_MS);
    complete(location.search).then((next) => location.replace(next), (e: unknown) => {
      setError(e instanceof SignInError ? t(`web-login.${e.key}`) : t("web-login.unreachable", { name: NAME, error: String(e) }));
    }).finally(() => clearTimeout(timer));
    return () => clearTimeout(timer);
  }, []);
  if (error !== null) {
    return <Page title={t("web-login.failed")} lead={error}><Button primary onClick={() => void start("/")}>{t("web-login.again")}</Button></Page>;
  }
  if (!slow) return <Page title={t("web-login.signingIn")} />;
  return (
    <Page title={t("web-login.signingIn")} lead={t("web-login.slow")}>
      <Button primary onClick={() => location.reload()}>{t("web-login.reload")}</Button>
      <Button onClick={() => location.replace("/")}>{t("web-login.again")}</Button>
    </Page>
  );
}
