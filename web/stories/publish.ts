// A chat shared as a picture for the stories (../src/Publish.tsx): the demo chat's info offering 分享图片, and what the
// picture would hold as the core says it (`chat.publishPreview`, client/core-ts/src/views/publish.ts): the chat's own
// messages as its list draws them (the visitor's in their bubble, an agent's words, its request about a vault item as
// its card, someone's files to tick), what was hidden in one said under it.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { ChatMessage, ChatView, PublishFile, PublishMessage, PublishPreview } from "../src/core/shapes.ts";
import { LIN, SAFARI_KEY, stamp } from "../src/demo/fixtures.ts";
import { markdown } from "../../client/core-ts/src/markdown.ts";
import { SENT, readFile } from "./data.ts";

const AGENT = { name: "Claude Opus 5.5", agent: "ember:c-demo-share", maker: { id: "anthropic", name: "Anthropic" }, runtime: "claude" as const };

/** A message of the picture's, said `minutes` ago. */
function said(seq: number, minutes: number, rest: Partial<ChatMessage> & Pick<ChatMessage, "authorKind" | "author" | "by" | "text">): ChatMessage {
  const at = Date.now() - minutes * 60_000;
  return { seq, thread: 7, ts: `${seq}`, attachments: [], quotes: [], createdAt: at, mine: false, system: false, waiting: false, time: { createdAt: stamp(at) }, ...rest };
}

function preview(): PublishPreview {
  // (kept by the chat's agent's session, as the core says of each: what its picture is read through)
  const sent = [SENT.picture, ...SENT.files.slice(0, 1)].map((file) => ({ ...file, owner: SAFARI_KEY }));
  const files: PublishFile[] = sent.map((file, i) => ({ k: `f${i}`, name: file.name, size: file.size, sizeText: `${Math.ceil(file.size / 1024)} KB`, type: "", n: 9, file }));
  const deployed = "部署好了：**登录后跳回原页面**，`npm run deploy:staging` 跑了 42 秒。";
  const list = [
    said(4, 12, { authorKind: "person", author: "local", mine: true, by: { name: "你" }, text: "帮我把登录页部署到预发，token 是 [已隐藏]" }),
    said(6, 10, { authorKind: "agent", author: AGENT.agent, by: AGENT, text: deployed, md: markdown(deployed) }),
    said(7, 9, {
      authorKind: "agent", author: AGENT.agent, by: AGENT, text: "申请使用「Axiom 查询 token」：查登录页的错误日志",
      card: { type: "options", vault: "r-axiom", vaultAsk: { name: "Axiom 查询 token", reason: "查登录页的错误日志", mode: "proxy", hosts: ["api.axiom.co"], command: "curl -s https://api.axiom.co/v1/datasets/_apl -H \"Authorization: Bearer $AXIOM_TOKEN\"" } },
    }),
    said(9, 8, { authorKind: "person", author: LIN.id, by: { name: LIN.name }, text: "截图和慢查询记录都附上了", attachments: sent }),
  ];
  const messages: PublishMessage[] = list.map((m) => ({
    n: m.seq, author: m.by.name, agent: m.authorKind === "agent", text: m.text, files: files.filter((f) => f.n === m.seq), createdAt: m.createdAt,
    ...(m.seq === 4 ? { hidden: 1, hiddenText: "已隐藏 1 处" } : { hidden: 0 }),
  }));
  return { upto: 9, title: "部署登录页", list, messages, files, hidden: 1, hiddenText: "共隐藏 1 处疑似机密" };
}

/** The demo with its chats' info offering 分享图片, the picture it would make of one, and its files' pictures. */
export function shareImageDemo(): DemoExtension {
  return {
    then: (t, value) => (t.topic === "chat" && value ? { ...(value as ChatView), publish: { may: true, links: [] } } : undefined),
    call: (name, p) => (name === "chat.publishPreview" ? preview() : name === "station.file" ? readFile(String(p.name), 0, Number.MAX_SAFE_INTEGER) : undefined),
  };
}
