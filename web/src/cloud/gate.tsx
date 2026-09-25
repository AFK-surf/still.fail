// Pieces shared by ember cloud's pages and the station frame: who is signed in, and the sign-in page.
import { useEffect, useState, type ReactNode } from "react";
import { Button } from "../ui.tsx";
import { accounts, signIn, type Account } from "./accounts.ts";
import type { StationView } from "./api.ts";

/** Seen within the last few heartbeats (one a minute). */
export const online = (s: StationView) => s.last_seen !== null && Date.now() / 1000 - s.last_seen < 150;

export function useAccounts(): Account[] {
  const [list, setList] = useState(accounts);
  useEffect(() => {
    const update = () => setList(accounts());
    window.addEventListener("ember-accounts", update);
    window.addEventListener("storage", update);
    return () => {
      window.removeEventListener("ember-accounts", update);
      window.removeEventListener("storage", update);
    };
  }, []);
  return list;
}

export function Avatar({ account, size = 24 }: { account: { name: string; email: string; picture: string }; size?: number }) {
  const letter = ([...(account.name || account.email)][0] ?? "?").toUpperCase();
  const [broken, setBroken] = useState(false);
  return account.picture && !broken
    ? <img className="person" src={account.picture} alt="" width={size} height={size} referrerPolicy="no-referrer" onError={() => setBroken(true)} />
    : <span className="person person-letter" style={{ width: size, height: size, fontSize: size * .45 }} aria-hidden="true">{letter}</span>;
}

export function SignInPage({ lead }: { lead?: ReactNode }) {
  return (
    <div className="gate sign-in-page">
      <img src={`${import.meta.env.BASE_URL}ember.svg`} alt="" width={44} height={44} />
      <h1>登录 ember</h1>
      <p>{lead ?? "用 Google 账号登录，管理你的 workspace 和里面的 station。"}</p>
      <Button variant="primary" onClick={() => void signIn()}>使用 Google 账号登录</Button>
    </div>
  );
}

/** Shows the sign-in page until at least one account is signed in. */
export function SignInGate({ children }: { children: ReactNode }) {
  const list = useAccounts();
  return list.length === 0 ? <SignInPage /> : <>{children}</>;
}
