// Prototype client core: what the app's core does for the chat list (fetch a station's chats, keep them, build the
// rows the UI shows, again on every change), written once in TypeScript. The shell (../src/main.rs) gives it the
// network; the UI only hears `emit`. A plain script with erasable types only: Node strips them, QuickJS runs the result.

declare const host: {
  now(): number;
  log(text: string): void;
  emit(topic: string, value: string): void;
  save(text: string): void;
  connect(addr: string): Promise<string>;
  request(conn: number, body: string): Promise<string>;
};

type Chat = { id: string; title: string; station: string; updated: number; unread: number; pinned: boolean; state: string; last: string; people: string[] };
type Row = { id: string; title: string; preview: string; when: string; badge: number; mark: string; section: string };

const DAY = 86400000;
const MARKS: Record<string, string> = { running: "●", waiting: "◐", need_human: "!", all_done: "✓", idle: "" };

function startOfDay(t: number): number {
  const d = new Date(t);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

function when(t: number, now: number): string {
  const ago = now - t;
  if (ago < 60000) return "刚刚";
  if (ago < 3600000) return `${Math.floor(ago / 60000)} 分钟前`;
  if (ago < DAY) return `${Math.floor(ago / 3600000)} 小时前`;
  const date = new Date(t);
  return `${date.getMonth() + 1}月${date.getDate()}日`;
}

function section(t: number, now: number): string {
  const days = Math.round((startOfDay(now) - startOfDay(t)) / DAY);
  return days <= 0 ? "今天" : days === 1 ? "昨天" : days < 7 ? "这周" : "更早";
}

function view(chats: Chat[], query: string, now: number): Row[] {
  const q = query.trim().toLowerCase();
  const shown = q
    ? chats.filter((c) => c.title.toLowerCase().includes(q) || c.last.toLowerCase().includes(q) || c.people.some((p) => p.includes(q)))
    : chats.slice();
  shown.sort((a, b) => Number(b.pinned) - Number(a.pinned) || b.updated - a.updated || (a.id < b.id ? -1 : 1));
  return shown.map((c) => ({
    id: c.id,
    title: c.title,
    preview: c.last,
    when: when(c.updated, now),
    badge: c.unread,
    mark: MARKS[c.state] ?? "",
    section: c.pinned ? "置顶" : section(c.updated, now),
  }));
}

// The work, timed: the first list, 200 changes (a message lands in a chat; the list is rebuilt and handed to the UI
// whole), and searching as one types.
function bench(chats: Chat[]) {
  const now = Date.now();
  let t = host.now();
  let rows = view(chats, "", now);
  host.emit("chats", JSON.stringify(rows));
  const first = host.now() - t;
  t = host.now();
  for (let i = 0; i < 200; i++) {
    const chat = chats[(i * 37) % chats.length];
    chat.updated = now + i;
    chat.unread++;
    chat.last = `新消息 ${i}`;
    rows = view(chats, "", now + i);
    host.emit("chats", JSON.stringify(rows));
  }
  const update = (host.now() - t) / 200;
  t = host.now();
  const queries = ["部", "部署", "安卓", "station", "user1"];
  for (const q of queries) host.emit("chats", JSON.stringify(view(chats, q, now)));
  const search = (host.now() - t) / queries.length;
  return { chats: chats.length, first, update, search };
}

async function main(addr: string, n: number) {
  const t0 = host.now();
  const opened = JSON.parse(await host.connect(addr));
  if (opened.error) throw new Error(opened.error);
  const t1 = host.now();
  const body = await host.request(opened.id, JSON.stringify({ op: "chats", n }));
  if (body.startsWith("\0")) throw new Error(body.slice(1));
  const t2 = host.now();
  const answer = JSON.parse(body);
  const t3 = host.now();
  host.save(body);
  // Small requests one after another: the round trip through the shell, iroh and the station.
  const pings = 50;
  for (let i = 0; i < pings; i++) await host.request(opened.id, JSON.stringify({ op: "ping", i }));
  const roundTrip = (host.now() - t3) / pings;
  const work = bench(answer.chats);
  host.emit("result", JSON.stringify({ connect: t1 - t0, fetch: t2 - t1, bytes: body.length, parse: t3 - t2, roundTrip, ...work }));
}
