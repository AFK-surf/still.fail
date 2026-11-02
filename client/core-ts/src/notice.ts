// still.fail's own notices in a chat, as the clients draw them (the web's Chat.tsx SystemNotice, the desktop's
// sfdesk/message.mbt): self-contained, for the web's demo core too.

/** still.fail's notice as a chat shows it: a line of the UI, not prose. The station begins its failures with ⚠️ (Slack
 * shows it so): `failed`, the mark left out of `words`; no 。 at its end (stations before 2026-09-30 wrote them as
 * sentences). One about a profile (`profiled`: its sign-in failed): where what went wrong begins in `words`, after
 * its ：, which links to that profile's page. A failure the station says what failed said of under it (a code block
 * after its first paragraph, 2026-11-03): that apart, as `detail`, shown when the notice is opened. */
export function noticeOf(text: string, profiled: boolean): { failed: boolean; words: string; linkAt?: number; detail?: string } {
  const mark = /^⚠️\s*/u.exec(text);
  const all = mark ? text.slice(mark[0].length) : text;
  const block = /\n\n```\n([\s\S]*?)\n?```\s*$/u.exec(all);
  const words = (block ? all.slice(0, block.index) : all).replace(/。\s*$/u, "");
  const colon = profiled ? words.indexOf("：") : -1;
  const out: { failed: boolean; words: string; linkAt?: number; detail?: string } = { failed: mark !== null, words };
  if (colon >= 0) out.linkAt = colon + 1;
  if (block && block[1]!.trim() !== "") out.detail = block[1]!.trim();
  return out;
}

