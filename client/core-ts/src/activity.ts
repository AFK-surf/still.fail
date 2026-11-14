// What an agent at work is doing, as a chat shows it: one line, the thing it does now. From a `live`
// topic's value into `activity`: `{ now: { key, text } }`.
import { t } from "./i18n.ts";
import { cleanCommand, cleanPath, closeCut as close, summaryCommand } from "./tool-step.ts";
import { get } from "./util.ts";

/// A tool's name without its MCP prefix or ACP "Run " prefix.
export function toolName(tool: string): string {
  const s = tool.startsWith("Run ") ? tool.slice(4) : tool;
  for (const p of ["mcp__stillfail__", "mcp_stillfail_", "stillfail__", "stillfail.", "mcp__ember__", "mcp_ember_", "ember__", "ember."]) if (s.startsWith(p)) return s.slice(p.length);
  return s;
}

/// What kind of thing a tool does, for its icon and its verb. Claude Code's names, Codex's, DeepSeek Harness's
/// (lowercase: read, bash, …), and ACP/Antigravity's ("File …", read_file, edit_file, write_file, run_command, …).
export function kindOf(tool: string, input?: string | Record<string, J> | null): string {
  const name = toolName(tool);
  if (name.endsWith(" on Web")) return "web";
  const a = typeof input === "string" ? args(input) : input ?? null;
  if (
    name.startsWith("File ") ||
    name === "read_file" ||
    name === "edit_file" ||
    name === "write_file" ||
    name === "write_to_file" ||
    name === "replace_file_content" ||
    name === "multi_replace_file_content" ||
    name === "search_replace" ||
    name === "delete_file"
  ) {
    if (
      name === "edit_file" ||
      name === "replace_file_content" ||
      name === "multi_replace_file_content" ||
      name === "write_file" ||
      name === "write_to_file" ||
      name === "search_replace" ||
      name === "delete_file"
    ) {
      return "edit";
    }
    if (name === "read_file") return "read";
    if (a && (a.Target !== undefined || a.Replacement !== undefined || a.Content !== undefined || a.old_string !== undefined || a.new_string !== undefined || a.content !== undefined)) return "edit";
    return "read";
  }
  switch (name) {
    case "Read":
    case "NotebookRead":
    case "view_image":
    case "read_image":
    case "read":
    case "view_file_outline":
    case "view_code_item":
    case "skill_read":
    case "skill":
      return "read";
    case "Glob":
    case "Grep":
    case "LS":
    case "ToolSearch":
    case "search_tool":
    case "mcp_list_tools":
    case "glob":
    case "grep":
    case "grep_search":
    case "find_by_name":
    case "find_file_by_name":
    case "list_dir":
    case "search":
      return "search";
    case "Edit":
    case "MultiEdit":
    case "Write":
    case "NotebookEdit":
    case "apply_patch":
    case "edit":
    case "write":
      return "edit";
    case "Bash":
    case "bash":
    case "BashOutput":
    case "KillShell":
    case "exec_command":
    case "exec":
    case "shell":
    case "local_shell":
    case "write_stdin":
    case "wait":
    case "job_output":
    case "unified_exec":
    case "run_command":
    case "run_terminal_command":
    case "command_status":
    case "send_command_input":
    case "manage_task":
    case "sleep":
    case "get_output":
      return "command";
    case "WebFetch":
    case "WebSearch":
    case "web_search":
    case "web_fetch":
    case "search_web":
    case "read_url_content":
    case "web__run":
      return "web";
    case "Task":
    case "spawn_agent":
    case "subagent":
    case "invoke_subagent":
      return "agent";
    case "Agent":
      return typeof a?.Action === "string" || typeof a?.action === "string" ? "other" : "agent";
    case "swarm":
      return a?.action === "add" ? "agent" : "other";
    case "define_subagent":
    case "manage_subagents":
    case "send_message":
    case "SendMessage":
    case "followup_task":
    case "list_agents":
    case "wait_agent":
      return "other";
    case "chat_history":
    case "chat_list":
    case "chat_read":
    case "session_history":
    case "session_send":
    case "chat_archive":
    case "chat_leave":
      return "thread";
    default:
      if (a && typeof a.CommandLine === "string") return "command";
      if (a && (a.Target !== undefined || a.Replacement !== undefined || a.Content !== undefined)) return "edit";
      if (a && (typeof a.Path === "string" || typeof a.target_file === "string")) return "read";
      if (/^(?:cd|git|pnpm|npm|node|cargo|python3?|sh|bash|zsh|rg|ls|cat|mkdir|rm|cp|mv|curl|gh)\b/.test(name)) return "command";
      return "other";
  }
}

/// Steps worth retaining briefly in the chat's activity even if they finish quickly. A shell command or an unknown
/// tool can do many different things, so its importance is not guessed from its words. Routine reads, searches and
/// remote task status checks can instead be coalesced when the agent moves on at once.
export function importantCall(tool: string, input: string): boolean {
  const name = toolName(tool);
  const kind = kindOf(tool, input);
  if (kind === "edit" || kind === "agent") return true;
  if (name === "station_task") return args(input)?.action === "start";
  return ["request_user_input", "request_user_input_async", "chat_create", "session_send", "job_start"].includes(name);
}

function verb(kind: string): string {
  return ["read", "search", "edit", "command", "web", "agent", "thread"].includes(kind) ? t(`core-logic.activity.verb.${kind}`) : t("core-logic.activity.verb.other");
}

// deno-lint-ignore no-explicit-any
type J = any;

function parseObject(text: string): Record<string, J> | null {
  try {
    const v = JSON.parse(text);
    return v !== null && typeof v === "object" && !Array.isArray(v) ? v : null;
  } catch {
    return null;
  }
}

/// A call's input as an object: whole, kept to its first characters (a transcript's `… (n more characters)`), or cut
/// short anywhere (an older station's live step carried its first 300 characters).
export function args(text: string): Record<string, J> | null {
  try {
    const v = JSON.parse(text);
    return v !== null && typeof v === "object" && !Array.isArray(v) ? v : null;
  } catch {
    // Not whole: read below.
  }
  // A long call is kept to its first characters, then `… (n more characters)`: read what is there.
  const at = text.lastIndexOf("\n… (");
  if (at >= 0 && text.endsWith(" more characters)")) return cutShort(text.slice(0, at));
  return text.trimStart().startsWith("{") ? cutShort(text) : null;
}

/// JSON cut short, read as far as it goes: closed where it stops, or (cut in a key, `{"a":"x","descr`) at the field before.
function cutShort(json: string): Record<string, J> | null {
  const whole = parseObject(close(json));
  if (whole) return whole;
  let quoted = false;
  let escaped = false;
  let comma = -1;
  for (let i = 0; i < json.length; i++) {
    const c = json[i];
    if (escaped) escaped = false;
    else if (quoted) {
      if (c === "\\") escaped = true;
      else if (c === '"') quoted = false;
    } else if (c === '"') quoted = true;
    else if (c === ",") comma = i;
  }
  return comma < 0 ? null : parseObject(close(json.slice(0, comma)));
}


const firstLine = (s: string) => (s.split(/\r?\n/).find((l) => l.trim() !== "") ?? "").trim();

/// What a call's words need beyond its input: the workspace's stations' names by id, and what the tasks prepared on
/// them earlier in the transcript run, by `<station>/<key>` (tasksOf).
export type Known = { stations?: ReadonlyMap<string, string>; tasks?: ReadonlyMap<string, string> };

/// The line of a command that says what it does: not `exec 2>&1`, `set -e`, a comment or a shebang.
function commandLine(command: string): string {
  const lines = command.split(/\r?\n/).map((l) => l.trim()).filter((l) => l !== "" && !/^(#|set\s+-|exec\s+\d*[<>])/.test(l));
  return summaryCommand(lines.join("\n"));
}

function shortChatRef(raw: string): string {
  const s = raw.trim();
  if (!s) return "";
  const urlPart = s.includes("/chats/") ? (s.split("/chats/").pop() ?? s) : s;
  try {
    const decoded = decodeURIComponent(urlPart).replace(/^chat:/, "");
    return decoded.length > 28 ? `${decoded.slice(0, 24)}…` : decoded;
  } catch {
    return urlPart.length > 28 ? `${urlPart.slice(0, 24)}…` : urlPart;
  }
}

/// What a station task runs, in a few words: the name it was given, else its command.
function taskOf(a: Record<string, J>): string {
  const name = typeof a.name === "string" ? firstLine(a.name) : "";
  return name || (typeof a.command === "string" ? commandLine(a.command) : "");
}

/// The tasks a transcript prepares on other stations (station_task prepare), by `<station>/<key>`: what each runs.
export function tasksOf(timeline: J[]): Map<string, string> {
  const out = new Map<string, string>();
  for (const e of timeline) {
    if (e?.kind !== "tool_call" || typeof e.tool !== "string" || toolName(e.tool) !== "station_task" || typeof e.text !== "string") continue;
    const a = args(e.text);
    if (a?.action !== "prepare" || typeof a.station !== "string" || typeof a.key !== "string") continue;
    const what = taskOf(a);
    if (what) out.set(`${a.station}/${a.key}`, what);
  }
  return out;
}

/// A call of still.fail's own tools said in words rather than by its name: what it does on which station (station_task,
/// station_file), the tools it loads (ToolSearch's `select:`), and still.fail's workspace/chat/job/skill tools; null for any other.
export function told(tool: string, input: string, known: Known = {}): string | null {
  const name = toolName(tool);
  const a = args(input);
  if (name.endsWith(" on Web")) {
    const q = typeof a?.query === "string" && a.query ? firstLine(a.query) : firstLine(name.slice(0, -7).replace(/^["']|["']$/g, ""));
    return q ? `网页搜索「${q}」` : "网页搜索";
  }
  if (!a) return null;
  if (name === "station_task" || name === "station_file") {
    const id = typeof a.station === "string" ? a.station : "";
    // An id not among the workspace's (or not read yet) is not shown as its 64 hex digits.
    const station = known.stations?.get(id) ?? (id === "" || /^[0-9a-f]{16,}$/.test(id) ? t("core-logic.activity.remote.another") : id);
    const key = typeof a.key === "string" ? a.key : "";
    if (name === "station_file") {
      const path = typeof a.path === "string" ? (a.path.split("/").pop() ?? a.path) : "";
      return t(`core-logic.activity.remote.${a.direction === "download" ? "download" : "upload"}`, { station, what: path || key });
    }
    if (a.action === "list") return t("core-logic.activity.remote.list", { station });
    if (a.action === "mirrors") return `在 ${station} 上查看同步目录`;
    if (a.action === "clean") return `在 ${station} 上清理 ${typeof a.mirror === "string" && a.mirror ? a.mirror : "同步目录"}`;
    if (a.action === "release") return `在 ${station} 上释放 ${key || "同步目录"}`;
    if (!["prepare", "start", "get", "log", "stop"].includes(a.action)) return null;
    const what = (a.action === "prepare" ? taskOf(a) : "") || known.tasks?.get(`${id}/${key}`) || key;
    return t(`core-logic.activity.remote.${a.action}`, { station, what });
  }
  if (name === "station_list") {
    return typeof a.station === "string" && a.station ? `查看 station ${a.station}` : "查看 station 列表";
  }
  if (name === "skill_read") {
    const skill = typeof a.name === "string" ? a.name : "";
    const file = typeof a.file === "string" && a.file ? ` (${a.file})` : "";
    return skill ? `读取技能 ${skill}${file}` : "读取技能";
  }
  if (name === "chat_post") {
    if (typeof a.title === "string" && a.title && typeof a.text !== "string") return `设置对话标题「${a.title}」`;
    if (typeof a.withdraw === "string" && a.withdraw) return "撤回选项卡片";
    if (typeof a.send === "string" && a.send) return "发送暂存回复";
    return null;
  }
  if (name === "chat_read" || name === "chat_history" || name === "session_history" || name === "session_send" || name === "chat_archive" || name === "chat_leave") {
    const ref = shortChatRef(typeof a.chat === "string" ? a.chat : typeof a.to === "string" ? a.to : "");
    if (name === "chat_history") return ref ? `读取对话历史 ${ref}` : "读取对话历史";
    if (name === "chat_read") return ref ? `读取对话 ${ref}` : "读取对话";
    if (name === "session_history") return ref ? `读取执行历史 ${ref}` : "读取执行历史";
    if (name === "session_send") return ref ? `向 ${ref} 发送消息` : "向其他会话发送消息";
    if (name === "chat_archive") return ref ? `归档对话 ${ref}` : "归档对话";
    return ref ? `停止关注 ${ref}` : "停止关注对话";
  }
  if (name === "chat_list") {
    return typeof a.query === "string" && a.query ? `查找对话「${firstLine(a.query)}」` : "查看对话列表";
  }
  if (name === "search") {
    return typeof a.query === "string" && a.query ? `搜索工作区「${firstLine(a.query)}」` : "搜索工作区";
  }
  if (name === "job_start") {
    const jname = typeof a.name === "string" && a.name ? firstLine(a.name) : typeof a.command === "string" ? commandLine(a.command) : "";
    if (a.watch === true) return jname ? `启动监控任务 ${jname}` : "启动监控任务";
    if (typeof a.port === "number") return jname ? `启动服务 ${jname} (:${a.port})` : `启动服务 (:${a.port})`;
    return jname ? `启动后台任务 ${jname}` : "启动后台任务";
  }
  if (name === "job_list") return "查看后台任务列表";
  if (name === "job_log") return typeof a.id === "string" && a.id ? `查看后台任务日志 ${a.id}` : "查看后台任务日志";
  if (name === "job_stop") return typeof a.id === "string" && a.id ? `停止后台任务 ${a.id}` : "停止后台任务";
  if (name === "screen") {
    if (a.action === "take_control") return "接管屏幕控制";
    return typeof a.id === "string" && a.id ? `查看屏幕 ${a.id}` : "查看屏幕列表";
  }
  if (name === "browser") {
    return typeof a.action === "string" && a.action !== "endpoint" ? `浏览器 ${a.action}` : "启动会话浏览器";
  }
  if (name === "secret_list") return "查看密钥列表";
  if (name === "secret_describe") return typeof a.item === "string" && a.item ? `更新密钥说明 ${a.item}` : "更新密钥说明";
  if (name === "secret_reask") return "重新请求密钥授权";
  if (name === "secret_delete") return typeof a.item === "string" && a.item ? `申请删除密钥 ${a.item}` : "申请删除密钥";
  if (name === "secret_cancel") return "撤回密钥申请";
  if (name === "phone_use") return a.done === true ? "归还手机调试权限" : "请求手机调试权限";
  if (name === "phone_send") return typeof a.path === "string" && a.path ? `发送文件到手机 ${a.path.split("/").pop() ?? a.path}` : "发送文件到手机";
  if (name === "adb_devices") return "查看已连接 Android 设备";
  if (name === "device_list") return "查看工作区设备列表";
  if (name === "permissions") return typeof a.request === "string" && a.request ? `请求系统权限 ${a.request}` : "查看系统权限";
  if (name === "relays") {
    if (a.action === "add" || a.action === "remove") return `${a.action === "add" ? "添加" : "移除"}中继 ${typeof a.url === "string" ? a.url : ""}`.trim();
    return "查看中继列表";
  }
  if (name === "workspace_limit") return typeof a.limit_gib === "number" ? `设置工作区空间上限 ${a.limit_gib} GiB` : "查看工作区空间上限";
  if (name === "feishu_api") return typeof a.method === "string" && a.method ? `飞书 API ${a.method}` : "调用飞书 API";
  if (name === "station_tool") {
    const sub = typeof a.name === "string" ? a.name : "";
    return a.arguments ? `调用 ${sub}`.trim() : `查看工具说明 ${sub}`.trim();
  }
  if (name === "ToolSearch" || name === "search_tool") {
    if (typeof a.query === "string" && a.query.startsWith("select:")) {
      const names = a.query.slice("select:".length).split(",").map((n) => toolName(n.trim())).filter((n) => n !== "");
      if (names.length > 0) return t("core-logic.activity.tools", { names: names.join(t("core-logic.history.did.sep")) });
    }
    if (name === "search_tool") {
      return typeof a.query === "string" && a.query ? `查找工具「${firstLine(a.query)}」` : "查找工具";
    }
    return null;
  }
  if (name === "mcp_list_tools") return "查看可用 MCP 工具";
  if (name === "manage_task") {
    const act = typeof a.Action === "string" ? a.Action : typeof a.action === "string" ? a.action : "";
    const rawId = typeof a.TaskId === "string" ? (a.TaskId.split("/").pop() ?? a.TaskId) : "";
    const tid = rawId ? ` ${rawId}` : "";
    if (act === "list") return "查看后台命令列表";
    if (act === "status") return `查看后台命令状态${tid}`;
    if (act === "kill") return `停止后台命令${tid}`;
    if (act === "send_input") return `向后台命令发送输入${tid}`;
  }
  if (name === "sleep") return typeof a.seconds === "number" ? `等待 ${a.seconds} 秒` : "等待";
  if (name === "get_output") return typeof a.job_id === "string" && a.job_id ? `读取任务输出 ${a.job_id}` : "读取任务输出";
  if (name === "job_output") return typeof a.job_id === "string" && a.job_id ? `查看命令输出 ${a.job_id}` : "查看命令输出";
  if (name === "wait") {
    const cid = typeof a.cell_id === "string" && a.cell_id ? ` #${a.cell_id}` : "";
    return `等待命令输出${cid}`;
  }
  if (name === "write_stdin") {
    const sid = a.session_id !== undefined ? ` #${a.session_id}` : "";
    const chars = typeof a.chars === "string" ? firstLine(a.chars) : "";
    return chars ? `向命令发送输入${sid}：${chars}` : `等待命令输出${sid}`;
  }
  if (name === "skill") {
    const skill = typeof a.name === "string" && a.name ? a.name : typeof a.skill === "string" && a.skill ? a.skill : "";
    return skill ? `读取技能 ${skill}` : "读取技能";
  }
  if (name === "web__run") {
    if (Array.isArray(a.search_query) && a.search_query.length > 0) {
      const q = typeof a.search_query[0]?.q === "string" ? firstLine(a.search_query[0].q) : "";
      return q ? `网页搜索「${q}」` : "网页搜索";
    }
    if (Array.isArray(a.open) && a.open.length > 0) {
      const u = typeof a.open[0]?.ref_id === "string" ? firstLine(a.open[0].ref_id) : "";
      return u ? `打开网页 ${u}` : "打开网页";
    }
    return "网页操作";
  }
  if (name === "clock__curr_time") return "查看当前时间";
  if (name === "list_agents") return "查看子 agent 列表";
  if (name === "wait_agent") return "等待子 agent 完成";
  if (name === "send_message" || name === "SendMessage") {
    if (typeof a.summary === "string" && a.summary.trim() !== "") return firstLine(a.summary);
    const to = typeof a.Recipient === "string" && a.Recipient
      ? a.Recipient
      : typeof a.recipient === "string" && a.recipient
      ? a.recipient
      : typeof a.to === "string" && a.to
      ? a.to
      : typeof a.task_name === "string" && a.task_name
      ? a.task_name
      : "";
    const msg = typeof a.Message === "string" && !a.Message.startsWith("gAAAAAB")
      ? firstLine(a.Message)
      : typeof a.message === "string" && !a.message.startsWith("gAAAAAB")
      ? firstLine(a.message)
      : typeof a.content === "string"
      ? firstLine(a.content)
      : "";
    const snippet = msg ? `：${msg.length > 36 ? `${msg.slice(0, 36)}…` : msg}` : "";
    if (!to || to === "main") return `向主 agent 发送结果${snippet}`;
    const shortTo = to.length > 16 ? to.slice(0, 8) : to;
    return `向子 agent (${shortTo}) 发送消息${snippet}`;
  }
  if (name === "followup_task") {
    const tname = typeof a.task_name === "string" && a.task_name ? ` ${a.task_name}` : "";
    return `继续子 agent 任务${tname}`;
  }
  if (name === "manage_subagents" || name === "swarm" || name === "Agent" || name === "Task" || name === "spawn_agent" || name === "subagent" || name === "invoke_subagent" || name === "define_subagent") {
    if (typeof a.Action === "string") {
      if (a.Action === "list") return "查看子 agent 列表";
      if (a.Action === "kill") return "停止子 agent";
      if (a.Action === "kill_all") return "停止全部子 agent";
    }
    if (typeof a.action === "string") {
      if (a.action === "status") return "查看协作 agent 状态";
      if (a.action === "models") return "查看可用模型列表";
      if (a.action === "add") return typeof a.name === "string" && a.name ? `添加协作 agent ${a.name}` : "添加协作 agent";
      if (a.action === "kill") return typeof a.name === "string" && a.name ? `停止协作 agent ${a.name}` : "停止协作 agent";
      if (a.action === "model") return typeof a.name === "string" && a.name ? `切换协作 agent 模型 ${a.name}` : "切换模型";
      if (a.action === "title") return typeof a.title === "string" && a.title ? `设置协作标题「${firstLine(a.title)}」` : "设置协作标题";
    }
    if (typeof a.Role === "string" && a.Role) return `分派子 agent：${firstLine(a.Role)}`;
    if (typeof a.task_name === "string" && a.task_name) return `分派子 agent：${firstLine(a.task_name)}`;
    if (typeof a.Name === "string" && a.Name && name === "define_subagent") return `定义子 agent：${firstLine(a.Name)}`;
  }
  return null;
}

/// What a call does, in a few words: what still.fail's own tools say of it (told), else its own description, else its
/// verb and what it works on. The chat's activity says a running call so, and an execution history names a group of
/// calls by its latest the same way.
export function doing(tool: string, input: string, known: Known = {}): string {
  const own = told(tool, input, known);
  if (own) return own;
  const a = args(input) ?? {};
  const desc = typeof a.description === "string"
    ? a.description
    : typeof a.toolSummary === "string"
    ? a.toolSummary
    : typeof a.summary === "string"
    ? a.summary
    : "";
  const said = firstLine(desc);
  if (said) return said;
  const kind = kindOf(tool, a);
  const keys =
    kind === "search"
      ? ["pattern", "Pattern", "query", "Query", "queries", "path", "Path", "target_directory", "DirectoryPath", "SearchDirectory", "SearchPath", "file_path", "url"]
      : ["command", "cmd", "CommandLine", "file_path", "target_file", "path", "Path", "target_directory", "DirectoryPath", "pattern", "Pattern", "url", "query", "Query", "queries", "prompt", "Prompt", "message", "Message", "text", "reason", "title", "Role", "to", "Recipient", "recipient"];
  let target = "";
  for (const name of keys) {
    const v = a[name];
    const s = typeof v === "string" ? v : Array.isArray(v) ? v.filter((p): p is string => typeof p === "string").join(" ") : null;
    if (s === null) continue;
    const isCmd = name === "command" || name === "cmd" || name === "CommandLine";
    const isPath = name === "file_path" || name === "target_file" || name === "path" || name === "Path" || name === "target_directory" || name === "DirectoryPath" || name === "SearchDirectory" || name === "SearchPath";
    const raw = isCmd ? summaryCommand(s) : isPath ? cleanPath(s) : s;
    const line = firstLine(raw);
    target = kind === "read" || kind === "edit" ? (line.split("/").pop() ?? line) : line;
    break;
  }
  if (!target && tool.startsWith("File ")) {
    const p = cleanPath(tool.slice(5).trim());
    target = p.split("/").pop() ?? p;
  } else if (!target && kind === "command" && !["Bash", "bash", "run_command", "run_terminal_command", "exec", "exec_command", "shell", "local_shell"].includes(toolName(tool))) {
    target = firstLine(summaryCommand(toolName(tool)));
  }
  return `${kind === "other" ? toolName(tool) : verb(kind)} ${target}`.trim();
}

/// Milliseconds since the epoch of an RFC 3339 time; null for anything else.
export function epochMs(at: string): number | null {
  if (at.length < 19 || at[4] !== "-" || at[10] !== "T") return null;
  const num = (a: number, b: number) => {
    const s = at.slice(a, b);
    return /^[+-]?\d+$/.test(s) ? Number(s) : null;
  };
  const [y0, m, d, hh, mm, ss] = [num(0, 4), num(5, 7), num(8, 10), num(11, 13), num(14, 16), num(17, 19)];
  if ([y0, m, d, hh, mm, ss].some((v) => v === null)) return null;
  const fracMatch = at.slice(19).startsWith(".") ? /^\d*/.exec(at.slice(20))![0] : "";
  const ms = fracMatch === "" ? 0 : Number(`0.${fracMatch}`) * 1000;
  const y = m! <= 2 ? y0! - 1 : y0!;
  const era = Math.floor(y / 400);
  const yoe = y - era * 400;
  const doy = Math.trunc((153 * (m! > 2 ? m! - 3 : m! + 9) + 2) / 5) + d! - 1;
  const doe = yoe * 365 + Math.trunc(yoe / 4) - Math.trunc(yoe / 100) + doy;
  const days = era * 146097 + doe - 719468;
  return (((days * 24 + hh!) * 60 + mm!) * 60 + ss!) * 1000 + ms;
}
