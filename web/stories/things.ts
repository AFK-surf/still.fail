// What was said in a chat besides words (the core's `chatThings` view, Things.tsx): the demo chat's pictures and a
// video, files, links and pull requests, entered from the chat's info (its pull requests named there).
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { ChatThing, ChatThingsView } from "../src/core/shapes.ts";
import { stamp } from "../src/demo/fixtures.ts";
import { SENT, readFile } from "./data.ts";

export function thingsDemo(): DemoExtension {
  let owner = "";
  return {
    then: (t, value) => {
      // (the files kept by the chat's agent, as the core says whose a message's file is)
      if (t.topic === "chat" && value) owner = (value as { agents: { session: { key: string } }[] }).agents[0]?.session.key ?? owner;
      return undefined;
    },
    topic: (t) => (t.topic === "chatThings" ? things(String((t as { q?: string }).q ?? ""), owner) : undefined),
    // (a picture's bytes, and a video's still: the stories' picture)
    call: (name, p) => (name === "station.file" ? readFile(String(p.name), 0, Number.MAX_SAFE_INTEGER) : name === "station.poster" ? readFile("still.png", 0, Number.MAX_SAFE_INTEGER) : undefined),
  };
}

function things(q: string, owner: string): ChatThingsView {
  const now = Date.now();
  const at = (minutes: number) => now - minutes * 60_000;
  const thing = (key: string, seq: number, minutes: number, by: string, rest: Partial<ChatThing>): ChatThing =>
    ({ key, seq, createdAt: at(minutes), time: { createdAt: stamp(at(minutes)) }, by, ...rest });
  const file = (f: { name: string; path: string; size: number; width?: number; height?: number }) => ({ ...f, owner });
  const media = [
    thing("m1", 9, 5, "Claude Opus 5.5", { file: file(SENT.picture) }),
    thing("m2", 7, 25, "Claude Opus 5.5", { file: file(SENT.files[1]!) }),
    thing("m3", 3, 80, "林", { file: file({ ...SENT.picture, path: "/Users/lin/Downloads/login-375-old.png" }) }),
  ];
  const files = [thing("f1", 7, 25, "Claude Opus 5.5", { file: file(SENT.files[0]!) })];
  const links = [
    thing("https://www.youtube.com/watch?v=8pDqJVdNa44", 8, 12, "林", { url: "https://www.youtube.com/watch?v=8pDqJVdNa44", site: "www.youtube.com/watch", title: "在家用旧电脑搭一台 NAS", count: 2 }),
    thing("https://docs.example.com/release", 4, 60, "Claude Opus 5.5", { url: "https://docs.example.com/release", site: "docs.example.com/release", count: 1 }),
  ];
  const pull = (n: number, seq: number, minutes: number, title: string, state: string, failed = 0): ChatThing => thing(`acme/shop#${n}`, seq, minutes, "Claude Opus 5.5", {
    url: `https://github.com/acme/shop/pull/${n}`, repository: "acme/shop", number: n, title, state, count: 1,
    checks: { passed: 9, failed, pending: 0 }, updatedAt: at(minutes), time: { createdAt: stamp(at(minutes)), updatedAt: stamp(at(minutes)) },
  });
  const pulls = [
    pull(131, 9, 5, "列表里的图片按需解码", "open", 1),
    pull(128, 6, 30, "首页列表按天分组", "merged"),
    pull(127, 5, 45, "虚拟列表：按估计高度占位", "merged"),
    pull(124, 2, 90, "去掉旧的分页加载", "closed"),
  ];
  const words = q.toLowerCase().split(/\s+/).filter(Boolean);
  const having = (list: ChatThing[]) => list.filter((x) => words.every((w) => [x.file?.name, x.title, x.url].join(" ").toLowerCase().includes(w)));
  return {
    title: "首页改版",
    whole: true,
    counts: { media: media.length, files: files.length, links: links.length, pulls: pulls.length },
    media: having(media), files: having(files), links: having(links), pulls: having(pulls),
  };
}
