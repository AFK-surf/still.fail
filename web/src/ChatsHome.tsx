// The chats as a page of their own (the 搜索列表 layout, layout.ts): no sidebar; the search on top, typed into at once,
// narrowing the list in place (the core's `chatSearch`); under it 全部 / 我参与的, the archive and a new chat, then the
// chats as the sidebar lists them, by day. ↑/↓ pick a row from the search, from the chat last open, ↩ opens it. Each chat's bar leads back here
// (ListBack), with how the others are doing.
import { useEffect, useMemo, useRef, useState } from "react";
import { Link, NavLink, useLocation, useNavigate } from "react-router";
import { useChatSearch, useChats, type ChatItem } from "./api.ts";
import { chatTone, type ChatTone } from "./ChatMark.tsx";
import { Archive, Compose, Search, Settings } from "./icons.tsx";
import { OpenJobs } from "./OpenJobs.tsx";
import { ChatRow, rowKey, StationTrouble } from "./Sidebar.tsx";
import { stationBase, useOnlyMine } from "./station.tsx";
import { lastChat } from "./lastChat.ts";
import { shortcutOf } from "./keymap.ts";
import { ICON, Segmented, SkeletonRows, Tip } from "./ui.tsx";
import * as css from "./ChatsHome.css.ts";
import * as markCss from "./ChatMark.css.ts";
import * as sidebarCss from "./styles/sidebar.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as pagesCss from "./styles/pages.css.ts";

export function ChatsHome({ scope, newChat, settings, archive }: { scope: string; newChat: string; settings: string; archive: string }) {
  const navigate = useNavigate();
  const [onlyMine, setOnlyMine] = useOnlyMine();
  const [query, setQuery] = useState("");
  const typed = query.trim();
  const chats = useChats(scope, onlyMine);
  const search = useChatSearch({ scope, query: typed });
  const view = chats.value;
  const lead = view?.leading ?? "agents";
  // What is shown, in order: the list's rows, day by day as the sidebar has them; while something is typed, only those
  // the search found (in the list's order still), then any it found the list has not.
  const found = search.value?.items;
  const days = useMemo(() => {
    const listed = view?.days ?? [];
    if (!typed) return listed;
    if (!found) return [];
    const keys = new Set(found.map(rowKey));
    const kept = listed.map((d) => ({ ...d, items: d.items.filter((i) => keys.has(rowKey(i))) })).filter((d) => d.items.length > 0);
    const shown = new Set(kept.flatMap((d) => d.items.map(rowKey)));
    const rest = onlyMine ? [] : found.filter((i) => !shown.has(rowKey(i)));
    return rest.length ? [...kept, { label: "更早", daysAgo: 1e9, items: rest }] : kept;
  }, [view, typed, found, onlyMine]);
  const rows = useMemo(() => days.flatMap((d) => d.items), [days]);
  // The chat last open is the one picked to begin with: ↑/↓ move on from it.
  const last = decodeURIComponent(lastChat(scope, ""));
  const active = rows.findIndex((i) => decodeURIComponent(`${stationBase(i.station)}/chats/${encodeURIComponent(i.id)}`) === last);
  const [picked, setPicked] = useState<string | null>(null);
  const at = picked === null ? active : rows.findIndex((i) => rowKey(i) === picked);
  const pick = (i: number) => { const item = rows[i]; if (item) setPicked(rowKey(item)); };
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => {
    list.current?.querySelector(`[data-at="${at}"]`)?.scrollIntoView({ block: "nearest" });
  }, [at]);
  const open = (item: ChatItem | undefined) => {
    if (item) navigate(`${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`);
  };
  const keys = shortcutOf("chat.switch");
  let n = 0;
  return (
    <div className={css.home}>
      <header className={`${sidebarCss.pageBar} ${css.bar}`}>
        <div />
        <div />
        <div className={css.barActions}>
          <div className={css.station}><StationTrouble scope={scope} to={settings} /></div>
          <Tip label="设置"><Link className={pagesCss.iconBtn} to={settings} aria-label="设置"><Settings {...ICON} /></Link></Tip>
        </div>
      </header>
      <div className={css.scroll}>
        <div className={css.column}>
          {/* The search and what is beside it stay put; the list scrolls under them. */}
          <div className={css.head}>
          <label className={css.searchBox}>
            <Search size={18} />
            <input className={css.searchInput} autoFocus placeholder="搜索对话" aria-label="搜索对话" value={query} spellCheck={false}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => {
                if (e.nativeEvent.isComposing) return;
                const step = e.key === "ArrowDown" || e.ctrlKey && e.key === "n" ? 1 : e.key === "ArrowUp" || e.ctrlKey && e.key === "p" ? -1 : 0;
                if (step) { e.preventDefault(); pick(at < 0 ? (step > 0 ? 0 : rows.length - 1) : Math.max(0, Math.min(rows.length - 1, at + step))); }
                else if (e.key === "Enter") { e.preventDefault(); open(rows[Math.max(at, 0)]); }
                else if (e.key === "Escape" && query) { e.preventDefault(); setQuery(""); }
              }} />
            {keys && !query && <kbd className={css.searchKeys}>{keys}</kbd>}
          </label>
          <div className={css.tools}>
            <Segmented label="对话" value={onlyMine ? "mine" : "all"} onChange={(v) => setOnlyMine(v === "mine")}
              options={[{ value: "all", label: "全部" }, { value: "mine", label: "我参与的" }]} />
            <Link className={`${controlsCss.btn} ${controlsCss.btnGhost}`} to={archive}><Archive size={15} />已归档</Link>
            <Link className={`${controlsCss.btn} ${controlsCss.btnPrimary} ${css.newChat}`} to={newChat}><Compose size={15} />新建对话</Link>
          </div>
          </div>
          {!typed && <div className={css.jobs}><OpenJobs scope={scope} /></div>}
          <div ref={list} className={css.list}>
            {!typed && !view && !chats.error && <SkeletonRows />}
            {chats.error && !view && <p className={css.none}>{chats.error.message}</p>}
            {typed && search.error && !found && <p className={css.none}>更新 still.fail 后才能搜索对话</p>}
            {typed && found && rows.length === 0 && <p className={css.none}>没有找到对话</p>}
            {!typed && view && rows.length === 0 && <p className={css.none}>{onlyMine ? "没有你参与的对话" : "还没有对话"}</p>}
            {days.map((day) => (
              <section key={day.daysAgo} aria-label={day.label}>
                <div className={css.day}>{day.label}</div>
                {day.items.map((item) => {
                  const i = n++;
                  return <div key={rowKey(item)} className={css.row} data-at={i} data-picked={i === at || undefined}><ChatRow item={item} lead={lead} /></div>;
                })}
              </section>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

const ORDER: ChatTone[] = ["alert", "busy", "done"];
const SAID: Record<ChatTone, string> = { alert: "要处理", busy: "工作中", done: "有新消息" };

/**
 * A chat's way back to the list (the 搜索列表 layout), left of its title: how the other chats are doing, a dot of each
 * state with how many (as their rows' marks, ChatMark.tsx), so a chat that wants you is seen without leaving this one;
 * with nothing to say, 对话.
 */
export function ListBack({ scope, to }: { scope: string; to: string }) {
  const view = useChats(scope, false).value;
  const here = decodeURIComponent(useLocation().pathname);
  const counts = new Map<ChatTone, number>();
  for (const day of view?.days ?? []) for (const item of day.items) {
    if (`${stationBase(item.station)}/chats/${item.id}` === here) continue;
    const tone = chatTone(item);
    if (tone) counts.set(tone, (counts.get(tone) ?? 0) + 1);
  }
  const said = ORDER.filter((t) => counts.get(t)).map((t) => `${counts.get(t)} 个${SAID[t]}`).join("，");
  return (
    <Tip label={said ? `对话列表：${said}` : "对话列表"}>
      <NavLink className={css.back} to={to} aria-label={said ? `对话列表，${said}` : "对话列表"}>
        {!said && "对话"}
        {ORDER.filter((t) => counts.get(t)).map((t) => (
          <span key={t} className={css.backCount}><span className={markCss.chatMarkInline} data-tone={t} />{counts.get(t)}</span>
        ))}
      </NavLink>
    </Tip>
  );
}
