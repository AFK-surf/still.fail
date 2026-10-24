// still.fail's own notices in a chat, as the clients draw them (the web's Chat.tsx SystemNotice, the desktop's
// sfdesk/message.mbt): self-contained, for the web's demo core too.

/** still.fail's notice as a chat shows it: a line of the UI, not prose. The station begins its failures with ⚠️ (Slack
 * shows it so): `failed`, the mark left out of `words`; no 。 at its end (stations before 2026-09-30 wrote them as
 * sentences). One about a profile (`profiled`: its sign-in failed): where what went wrong begins in `words`, after
 * its ：, which links to that profile's page. */
export function noticeOf(text: string, profiled: boolean): { failed: boolean; words: string; linkAt?: number } {
  const mark = /^⚠️\s*/u.exec(text);
  const words = (mark ? text.slice(mark[0].length) : text).replace(/。\s*$/u, "");
  const colon = profiled ? words.indexOf("：") : -1;
  return colon >= 0 ? { failed: mark !== null, words, linkAt: colon + 1 } : { failed: mark !== null, words };
}

