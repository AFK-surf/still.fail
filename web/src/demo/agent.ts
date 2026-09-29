// The demo's agent, in this browser: what the visitor says in a chat goes to a model on their own key (llm.ts), which
// can look at and change the made-up repository (repo.ts); the chat and its execution panel show the turn as a
// station's would (its activity, its steps, its answer posted while the turn still runs).
import { addItem, groupOf, marked, message, posted, said, step, type DemoChat } from "./fixtures.ts";
import { makerOf, nameOf, type UserProfile } from "./keys.ts";
import { ask, LlmError, type Block, type Turn } from "./llm.ts";
import { describe, run, TOOLS } from "./repo.ts";
import type { HistoryStep } from "../core/shapes.ts";

const SYSTEM = [
  "你是 ember 里的一个 coding agent，在一个团队聊天的对话里工作。这是 ember 官网上的演示：你在浏览器里运行，面前是一个虚构的仓库 acme-web（React + Vite 的前端），只能用给你的工具看文件、搜索、改文件；不能运行命令、不能联网。",
  "用中文回复，简洁直接，像同事在聊天里说话。需要看代码时先用工具看，再回答；改了文件就说改了哪里。",
  "被问到你做不到的事（跑命令、部署、访问真实系统），说明这是演示，装好 ember 的 station 之后真实的 agent 就能做。",
].join("\n");

const MAX_STEPS = 8;

export interface Stage {
  publish(): void;
}

/** Answers the chat's latest message: the whole turn, as the station would run it. */
export async function runTurn(chat: DemoChat, profile: UserProfile, stage: Stage): Promise<void> {
  const model = profile.models.includes(chat.model.model) ? chat.model.model : profile.models[0]!;
  // The chat's agent runs on the visitor's account and model from here on (ember moves an agent off a refused account).
  chat.model = { runtime: "claude", model, name: nameOf(model), effort: "medium", maker: makerOf(model) ?? { id: "opencode", name: "OpenCode" } };
  chat.failed = false;
  chat.running = { activity: "思考中", since: Date.now() };
  stage.publish();

  // The conversation so far, as the model reads it: others' words with who said them.
  const messages: Turn[] = [];
  for (const m of chat.messages.slice(-16)) {
    if (m.system) continue;
    const role = m.authorKind === "agent" ? "assistant" : "user";
    const text = m.mine || m.authorKind === "agent" ? m.text : `${m.authorName ?? "有人"}：${m.text}`;
    const last = messages.at(-1);
    if (last && last.role === role && typeof last.content === "string") last.content += `\n\n${text}`;
    else messages.push({ role, content: text });
  }
  if (messages[0]?.role === "assistant") messages.shift();

  const steps: HistoryStep[] = [];
  let group = -1;
  try {
    for (let n = 0; n < MAX_STEPS; n++) {
      chat.running = { ...chat.running!, activity: n === 0 ? "思考中" : "请求模型中" };
      stage.publish();
      const { content } = await ask(profile, model, SYSTEM, messages, TOOLS);
      const text = content.filter((b): b is Extract<Block, { type: "text" }> => b.type === "text").map((b) => b.text).join("\n").trim();
      const uses = content.filter((b): b is Extract<Block, { type: "tool_use" }> => b.type === "tool_use");
      messages.push({ role: "assistant", content });
      if (!uses.length) {
        // Its answer: posted while the turn still runs, then the turn ends.
        const answer = text || "（模型没有回复内容）";
        chat.messages = [...chat.messages, message(chat, "agent", answer)];
        addItem(chat, posted(chat, answer));
        stage.publish();
        await new Promise((r) => setTimeout(r, 900));
        addItem(chat, marked("完成"));
        chat.running = null;
        stage.publish();
        return;
      }
      if (text) addItem(chat, said(text));
      const results: Block[] = [];
      for (const use of uses) {
        const shown = describe(use.name, use.input);
        chat.running = { ...chat.running!, activity: shown.activity };
        const pending = { ...step(shown.tool, shown.hint, use.input), said: text };
        const body = groupOf([...steps, pending], 1);
        if (group < 0 || group !== chat.items.length - 1) {
          addItem(chat, body);
          group = chat.items.length - 1;
          steps.length = 0;
        } else chat.items = chat.items.map((item, i) => (i === group ? { ...item, body } : item));
        stage.publish();
        const started = performance.now();
        const { result, failed } = run(use.name, use.input);
        await new Promise((r) => setTimeout(r, 450));
        steps.push(step(shown.tool, shown.hint, use.input, result, `${Math.round(performance.now() - started)}ms`, failed));
        chat.items = chat.items.map((item, i) => (i === group ? { ...item, body: groupOf(steps, 0) } : item));
        stage.publish();
        results.push({ type: "tool_result", tool_use_id: use.id, content: result, ...(failed ? { is_error: true } : {}) });
      }
      messages.push({ role: "user", content: results });
    }
    fail(chat, "⚠️ 这一轮出错了：步骤太多，演示里到这里先停下。", stage);
  } catch (e) {
    const notice = e instanceof LlmError && e.auth
      ? `⚠️ 运行时认证失败，需要管理员检查账号：${e.message}`
      : `⚠️ 这一轮出错了：${(e as Error).message}`;
    fail(chat, notice, stage);
  }
}

/** A turn that failed: ember says why in the chat, as the station does (session.rs failure_notice). */
function fail(chat: DemoChat, notice: string, stage: Stage): void {
  chat.running = null;
  chat.failed = true;
  chat.messages = [...chat.messages, message(chat, "ember", notice)];
  addItem(chat, marked("失败"));
  stage.publish();
}
