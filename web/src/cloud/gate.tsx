// Pieces shared by still.fail cloud's pages and the admin's console: people's
// avatars, the sign-in page and where a sign-in comes back to.
import { useEffect, useState, type ReactNode } from "react";
import { Key, Refresh } from "@stillfail/ui/icons.tsx";
import { Button } from "../ui.tsx";
import { completeSignIn, passwordSignIn, useSignIn } from "./accounts.ts";
import { useDoing } from "../doing.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import { Illustration } from "../brand.tsx";
import * as cloudCss from "../styles/cloud.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./gate.css.ts";
import { NAME } from "./beta.tsx";
import { standalone } from "../standalone.ts";
import { trackNow } from "../telemetry.ts";
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
          {t("web-pages.signIn.google")}
        </Button>
        <span className={css.or}>{t("web-pages.signIn.or")}</span>
        {password ? <PasswordSignIn /> : <Button variant="ghost" icon={Key} onClick={() => setPassword(true)}>{t("web-pages.signIn.password")}</Button>}
      </div>
    </div>
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
      <div className={css.fields}>
        <input className={controlsCss.input} type="email" autoComplete="username" autoFocus placeholder={t("web-pages.signIn.email")} aria-label={t("web-pages.signIn.email")} value={email} onChange={(e) => setEmail(e.target.value)} />
        <input className={controlsCss.input} type="password" autoComplete="current-password" placeholder={t("web-pages.signIn.passwordField")} aria-label={t("web-pages.signIn.passwordField")} value={password} onChange={(e) => setPassword(e.target.value)} />
      </div>
      {error && <div className={`${controlsCss.fieldError} ${css.passwordError}`} role="alert">{error}</div>}
      <Button type="submit" variant="primary" busy={busy} disabled={!email.trim() || !password}>{t("web-pages.signIn.passwordSubmit")}</Button>
    </form>
  );
}

/** How long the sign-in's last step may take before the page offers a way out: it takes a second or two. */
const SIGNING_IN_MS = 8000;

/**
 * /auth/callback: finishes the sign-in, then goes where it started. Taking far longer than it does (its core never
 * answering), it says so and offers to load the page again or to start over: an app on the home screen has no reload
 * of its own, and was stuck at 正在登录… for good (2026-10-09).
 */
export function Callback() {
  const [error, setError] = useState<string | null>(null);
  const [slow, setSlow] = useState(false);
  const signIn = useSignIn();
  useEffect(() => {
    const timer = setTimeout(() => { setSlow(true); void signInStuck(); }, SIGNING_IN_MS);
    completeSignIn().then((next) => location.replace(next), (e: Error) => setError(e.message)).finally(() => clearTimeout(timer));
    return () => clearTimeout(timer);
  }, []);
  return (
    <div className={shellCss.gate}>
      <Illustration name="sign-in" />
      <h1>{error ? t("web-pages.signIn.failed") : t("web-pages.signIn.signingIn")}</h1>
      {error && <><p>{error}</p><Button variant="primary" busy={signIn.busy} onClick={() => void signIn.signIn("/")}>{t("web-pages.signIn.again")}</Button></>}
      {!error && slow && (
        <>
          <p>{t("web-pages.signIn.slow")}</p>
          <div className={css.ways}>
            <Button variant="primary" icon={Refresh} onClick={() => location.reload()}>{t("common.reload")}</Button>
            <Button variant="ghost" onClick={() => location.replace("/")}>{t("web-pages.signIn.restart")}</Button>
          </div>
        </>
      )}
    </div>
  );
}

/**
 * The sign-in's last step stuck: told to telemetry with what holds the lock the core runs under (core/worker.ts) and
 * how many pages' workers are alive, and whether the page is an app on the home screen, to tell why it is.
 */
async function signInStuck(): Promise<void> {
  const locks = await navigator.locks?.query().catch(() => null);
  const core = (list: LockInfo[] | undefined) => list?.filter((l) => l.name === "stillfail-core").length ?? 0;
  trackNow("sign_in_stuck", {
    standalone: standalone(),
    coreHeld: core(locks?.held) > 0,
    coreWaiting: core(locks?.pending),
    workers: locks?.held?.filter((l) => l.name?.startsWith("stillfail-tab-")).length ?? 0,
  });
}
