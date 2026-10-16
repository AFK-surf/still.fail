// A person's tile, lettered and coloured by who they are: on its own, so a page without the app around it (the share
// page, web/src/share) draws people as the chat does.
import { vars } from "./styles/tokens.css.ts";
import * as partsCss from "./parts.css.ts";

const AVATAR_TONES = ["#c9954c", "#6f8fbf", "#7d9a6f", "#b07a9c", "#8c83c7", "#c77d6a"];

/** A lettered tile, coloured by id, like Zork's device avatars. */
export function Avatar({ id, name, size = 20 }: { id: string; name: string; size?: number }) {
  let hash = 0;
  for (const c of id) hash = (hash * 31 + c.charCodeAt(0)) >>> 0;
  // "ember-gpt" → G: the distinguishing last word, since connects often share a prefix.
  const word = name.trim().split(/[\s\-_./]+/).filter(Boolean).at(-1) ?? name;
  const letter = ([...word][0] ?? "?").toUpperCase();
  return (
    <span className={partsCss.avatar} aria-hidden="true"
      style={{ width: size, height: size, fontSize: Math.round(size * .52), background: AVATAR_TONES[hash % AVATAR_TONES.length], borderRadius: `calc(${Math.min(size * .375, 12)}px * ${vars.cornerScale})` }}>
      {letter}
    </span>
  );
}
