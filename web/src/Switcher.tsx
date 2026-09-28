// The shortcuts that belong to no page (keymap.ts), and ⌘K's switcher: a chat found by typing part of its title (↑/↓
// pick, ↩ opens, Esc closes, as everywhere; nothing says so).
import { Dialog as RDialog } from "radix-ui";
import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router";
import { useChats, type ChatItem } from "./api.ts";
import { Mark } from "./brand.tsx";
import { useShortcut } from "./keymap.ts";
import { stationBase } from "./station.tsx";
import { ModelLogo, Time } from "./ui.tsx";
import * as css from "./Switcher.css.ts";

/** Mounted once under a scope's pages (this station's, or a workspace's): its new chat and settings are at these paths. */
export function GlobalShortcuts({ scope, newChat, settings }: { scope: string; newChat: string; settings: string }) {
  const navigate = useNavigate();
  const [switching, setSwitching] = useState(false);
  useShortcut("chat.switch", () => setSwitching((s) => !s));
  useShortcut("chat.new", () => navigate(newChat));
  useShortcut("settings", () => navigate(settings));
  useShortcut("nav.back", () => history.back());
  useShortcut("nav.forward", () => history.forward());
  return <ChatSwitcher scope={scope} open={switching} onClose={() => setSwitching(false)} />;
}

function ChatSwitcher({ scope, open, onClose }: { scope: string; open: boolean; onClose(): void }) {
  return (
    <RDialog.Root open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <RDialog.Portal>
        <RDialog.Overlay className={css.overlay} />
        <RDialog.Content className={css.switcher} aria-describedby={undefined}>
          <RDialog.Title className={css.hidden}>切换对话</RDialog.Title>
          {open && <Finder scope={scope} onClose={onClose} />}
        </RDialog.Content>
      </RDialog.Portal>
    </RDialog.Root>
  );
}

/** Its chats as the sidebar lists them, newest first; typing narrows them to those whose title (or else where they are, or what was said last) has it. */
function Finder({ scope, onClose }: { scope: string; onClose(): void }) {
  const navigate = useNavigate();
  const view = useChats(scope, false).value;
  const [query, setQuery] = useState("");
  const [at, setAt] = useState(0);
  const list = useRef<HTMLDivElement>(null);
  const several = scope !== "local";
  const found = useMemo(() => {
    const all = (view?.days ?? []).flatMap((d) => d.items).filter((i) => !i.pending);
    const q = query.trim().toLowerCase();
    if (!q) return all;
    const has = (s: string | undefined) => !!s && s.toLowerCase().includes(q);
    const titled = all.filter((i) => has(i.title));
    const rest = all.filter((i) => !has(i.title) && (has(i.stationName) || has(i.originText) || has(i.last?.preview)));
    return [...titled, ...rest];
  }, [view, query]);
  useEffect(() => setAt(0), [query]);
  useEffect(() => {
    list.current?.querySelector(`[data-at="${at}"]`)?.scrollIntoView({ block: "nearest" });
  }, [at]);
  const go = (item: ChatItem | undefined) => {
    if (!item) return;
    onClose();
    navigate(`${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`);
  };
  return (
    <>
      <input className={css.search} autoFocus placeholder="搜索对话" aria-label="搜索对话" value={query} spellCheck={false}
        onChange={(e) => setQuery(e.target.value)}
        onKeyDown={(e) => {
          if (e.nativeEvent.isComposing) return;
          const step = e.key === "ArrowDown" || e.ctrlKey && e.key === "n" ? 1 : e.key === "ArrowUp" || e.ctrlKey && e.key === "p" ? -1 : 0;
          if (step) { e.preventDefault(); setAt((a) => Math.max(0, Math.min(found.length - 1, a + step))); }
          else if (e.key === "Enter") { e.preventDefault(); go(found[at]); }
        }} />
      <div className={css.results} ref={list} role="listbox" aria-label="对话">
        {view && found.length === 0 && <p className={css.none}>{query ? "没有找到对话" : "还没有对话"}</p>}
        {found.map((item, i) => (
          <div key={`${item.station}/${item.id}`} className={css.row} role="option" aria-selected={i === at} data-at={i}
            onMouseMove={() => { if (i !== at) setAt(i); }} onClick={() => go(item)}>
            <span className={css.picture} aria-hidden="true">
              {item.agents[0] ? <ModelLogo maker={item.agents[0].maker} runtime={item.agents[0].runtime} size={18} /> : <Mark size={16} />}
            </span>
            <span className={css.title} data-unread={item.unread || undefined}>{item.title}</span>
            <span className={css.meta}>
              {several && <span>{item.stationName}</span>}
              <Time stamp={item.time?.lastActiveAt} fixed />
            </span>
          </div>
        ))}
      </div>
    </>
  );
}
