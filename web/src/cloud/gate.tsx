// People's avatars in the admin's console: their picture, else their initial.
import { useState } from "preact/compat";
import * as cloudCss from "../styles/cloud.css.ts";

export function Avatar({ account, size = 24 }: { account: { name: string; email: string; picture: string }; size?: number }) {
  const letter = ([...(account.name || account.email)][0] ?? "?").toUpperCase();
  const [broken, setBroken] = useState(false);
  return account.picture && !broken
    ? <img className={cloudCss.person} src={account.picture} alt="" width={size} height={size} referrerPolicy="no-referrer" onError={() => setBroken(true)} />
    : <span className={`${cloudCss.person} ${cloudCss.personLetter}`} style={{ width: size, height: size, fontSize: size * .45 }} aria-hidden="true">{letter}</span>;
}
