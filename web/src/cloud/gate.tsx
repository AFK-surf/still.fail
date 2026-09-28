// Pieces shared by ember cloud's pages and the admin's console: people's
// avatars, the sign-in page and where a sign-in comes back to.
import { useEffect, useState, type ReactNode } from "react";
import { Button } from "../ui.tsx";
import { completeSignIn, signIn } from "./accounts.ts";
import { Illustration } from "../brand.tsx";
import * as cloudCss from "../styles/cloud.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./gate.css.ts";

export function Avatar({ account, size = 24 }: { account: { name: string; email: string; picture: string }; size?: number }) {
  const letter = ([...(account.name || account.email)][0] ?? "?").toUpperCase();
  const [broken, setBroken] = useState(false);
  return account.picture && !broken
    ? <img className={cloudCss.person} src={account.picture} alt="" width={size} height={size} referrerPolicy="no-referrer" onError={() => setBroken(true)} />
    : <span className={`${cloudCss.person} ${cloudCss.personLetter}`} style={{ width: size, height: size, fontSize: size * .45 }} aria-hidden="true">{letter}</span>;
}

export function SignInPage({ title = "登录 ember", lead }: { title?: string; lead?: ReactNode }) {
  return (
    <div className={`${shellCss.gate} ${css.signInPage}`}>
      <Illustration name="sign-in" />
      <h1>{title}</h1>
      <p>{lead ?? "用 Google 账号登录，管理你的 workspace 和里面的 station。"}</p>
      <Button variant="primary" onClick={() => void signIn()}>使用 Google 账号登录</Button>
    </div>
  );
}

/** /auth/callback: finishes the sign-in, then goes where it started. */
export function Callback() {
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    completeSignIn().then((next) => location.replace(next), (e: Error) => setError(e.message));
  }, []);
  return (
    <div className={shellCss.gate}>
      <Illustration name="sign-in" />
      <h1>{error ? "登录没有完成" : "正在登录…"}</h1>
      {error && <><p>{error}</p><Button variant="primary" onClick={() => void signIn("/")}>重新登录</Button></>}
    </div>
  );
}
