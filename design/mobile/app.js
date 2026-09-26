// ember mobile concept: a clickable phone. Fake data, simulated live work.
const $ = (s, el = document) => el.querySelector(s);
const device = $("#device");
const screensEl = $("#screens");
const overlay = $("#overlay");
const dark = () => device.dataset.theme === "dark";
const face = (state) => `assets/${state}${dark() ? "-dark" : ""}.svg`;
// Agents are their model: the maker's mark, as on the web. The buddy is ember itself (stations, app icon, illustrations).
const maker = (m) => (/gpt|codex|astra/i.test(m) ? "openai" : /claude|opus|sonnet/i.test(m) ? "anthropic" : /glm/i.test(m) ? "zhipu" : "deepseek");
const modelLogo = (m, cls = "") => `<span class="mlogo ${cls}"><img src="assets/${maker(m)}.svg" alt="" class="${maker(m) === "openai" || maker(m) === "anthropic" ? "mono" : ""}"></span>`;
// A chat can have several agents (models): their marks overlap, the state badge on the front one.
const modelStack = (models, badge) => models.length < 2 ? modelLogo(models[0], badge)
  : `<span class="mstack ${badge}">${models.slice(0, 2).map((m) => `<span class="mlogo pair"><img src="assets/${maker(m)}.svg" alt="" class="${maker(m) === "openai" || maker(m) === "anthropic" ? "mono" : ""}"></span>`).join("")}</span>`;
const esc = (s) => String(s ?? "").replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]);

// ── data ─────────────────────────────────────────────────────────
const people = { me: { name: "左子健", short: "左", color: "#5B7BB2" }, bob: { name: "Bob", short: "B", color: "#2F8F5B" }, lin: { name: "林", short: "林", color: "#B9471F" } };
const peopleStack = (ids, size = 18) => `<span class="pstack">${ids.map((id) => `<span class="pav" style="width:${size}px;height:${size}px;font-size:${Math.round(size * .5)}px;background:${people[id].color}">${people[id].short}</span>`).join("")}</span>`;
const workspaces = [
  { id: "3720", name: "3720", account: "zuozijian@gmail.com", stations: 3 },
  { id: "acme", name: "产品团队", account: "zuozijian@gmail.com", stations: 1 },
  { id: "dev", name: "Dev 测试", account: "alice@example.test", stations: 2 },
];
let ws = workspaces[0];
let onlyMine = false;
// Who started a chat: the first of its people. Others' chats carry their starter's avatar in the list.
const starter = (s) => s.people?.[0] ?? "me";
const byOther = (s) => starter(s) !== "me" ? `<span class="starter" title="${people[starter(s)].name} 发起">${peopleStack([starter(s)], 16)}</span>` : "";

const stations = [
  { id: "studio", name: "studio", host: "Mac Studio · M2 Max", online: true, cpu: 38, mem: 47, disk: 34, agents: 2, profiles: [
    { name: "OpenCode Go · Claude Code", models: ["deepseek-flash", "deepseek-v4-pro", "glm-5.2"], on: ["deepseek-flash", "deepseek-v4-pro"], quota: 32 },
    { name: "OpenCode Go · Codex", models: ["deepseek-flash", "gpt-6-astra"], on: ["gpt-6-astra"], quota: 61 },
  ] },
  { id: "mac-mini", name: "mac-mini", host: "Mac mini · M4", online: true, cpu: 12, mem: 58, disk: 71, agents: 0, profiles: [
    { name: "团队 Claude 订阅", models: ["claude-opus-5-5", "claude-sonnet-5"], on: ["claude-sonnet-5"], quota: 84 },
  ] },
  { id: "mba", name: "mba", host: "MacBook Air", online: false, cpu: 0, mem: 0, disk: 0, agents: 0, profiles: [] },
];

const sessions = [
  { id: "staging", title: "staging 早上发不出通知", station: "studio", source: "slack", model: "deepseek-flash", models: ["deepseek-flash", "gpt-6-astra"], people: ["me", "bob"], effort: "high", state: "block", when: "3 分钟前",
    question: "要我把告警规则改成 UTC 并重启 notifier 吗？重启会让推送中断大约 1 分钟。",
    quick: ["改吧，现在重启", "先别重启", "我来看看"],
    messages: [
      { mine: true, text: "帮我看一下 staging 为什么今天早上发不出通知，日志在 backroom" },
      { agent: true, model: "deepseek-flash", html: "<p>找到原因了：通知服务的日志时间戳是 <code>UTC</code>，但告警规则按北京时间配置，所以早上 8 点前的通知全被过滤掉了。</p><pre>rule: quiet_hours 00:00–08:00 (Asia/Shanghai)\nlog:  2026-09-26T00:12:04Z  suppressed</pre>" },
      { person: "bob", text: "mac-mini 上那套也是一样的配置，顺便一起看看？" },
      { agent: true, model: "gpt-6-astra", html: "<p>我看了 mac-mini：同一份规则文件，改一处两边都会生效。</p>" },
      { agent: true, model: "deepseek-flash", block: true, html: "<p>要我把告警规则改成 UTC 并重启 notifier 吗？重启会让推送中断大约 1 分钟。</p>" },
    ],
    history: [
      ["recv", "收到来自 左 的消息", "帮我看一下 staging 为什么今天早上发不出通知…"],
      ["group", "读取 backroom 日志 · 共 4 项"],
      ["group", "对比告警规则和日志时区 · 共 3 项"],
      ["post", "发出回复", "找到原因了：通知服务的日志时间戳是 UTC…"],
      ["post", "进入 block 状态", "要我把告警规则改成 UTC 并重启 notifier 吗？"],
    ] },
  { id: "zork", title: "跑一下 zork 的 android 测试，失败的话看看是哪个", station: "studio", source: "ember", model: "gpt-6-astra", models: ["gpt-6-astra"], people: ["me"], effort: "medium", state: "running", when: "进行中",
    steps: ["构建 debug 包", "启动 emulator-5580", "安装 ing.zork.android.test", "运行 42 个测试 · 9/42", "运行 42 个测试 · 23/42", "运行 42 个测试 · 36/42", "整理失败用例"],
    messages: [{ mine: true, text: "跑一下 zork 的 android 测试，失败的话看看是哪个" }],
    history: [["recv", "收到来自 你 的消息", "跑一下 zork 的 android 测试…"], ["group", "构建 debug 包 · 共 3 项"]] },
  { id: "weekly", title: "整理 bridge 值班周报", station: "mac-mini", source: "slack", model: "claude-sonnet-5", models: ["claude-sonnet-5", "deepseek-flash"], people: ["lin", "bob", "me"], effort: "", state: "running", when: "进行中",
    steps: ["读取值班频道 7 天的消息", "汇总 12 起告警", "写周报"], messages: [{ mine: true, text: "整理一下这周 bridge 值班的周报" }], history: [] },
  { id: "rebase", title: "rebase 和 squash 各自适用的场景", station: "studio", source: "slack", model: "deepseek-flash", models: ["deepseek-flash"], people: ["bob"], effort: "", state: "done", when: "10:38",
    messages: [{ mine: true, text: "用一句话总结 rebase 和 squash 各自适用的场景" }, { agent: true, html: "<p><b>rebase</b>：想保留每个提交、把分支接到最新主干上时用；<b>squash</b>：一个功能的零碎提交想合成一个干净提交时用。</p>" }], history: [] },
  { id: "png", title: "生成一张 300×200 的纯色 PNG", station: "studio", source: "ember", model: "deepseek-flash", models: ["deepseek-flash"], people: ["me"], effort: "", state: "done", when: "09:29",
    messages: [{ mine: true, text: "用 python3 生成一张 300×200 的纯色 PNG，发给我" }, { agent: true, html: "<p>好了，纯 Python 手写的 PNG 编码器，没依赖 Pillow。</p>", image: true }], history: [] },
  { id: "deploy", title: "部署 ember cloud 到生产", station: "studio", source: "slack", model: "deepseek-v4-pro", models: ["deepseek-v4-pro", "claude-sonnet-5"], people: ["me", "lin"], effort: "high", state: "failed", when: "昨天",
    messages: [{ mine: true, text: "部署一下 ember cloud" }, { agent: true, html: "<p>部署失败：wrangler 需要重新登录（<code>Authentication error [code: 10000]</code>）。</p>" }], history: [] },
];
const byId = (id) => sessions.find((s) => s.id === id);

// ── navigation ───────────────────────────────────────────────────
let stack = [];
let tab = "home";
// The app has no tab bar: chats are the home; stations and settings are pages off it.
function showTabbar() { $("#tabbar").classList.add("hidden"); }
function mount(name, arg) {
  const el = document.createElement("section");
  el.className = "screen";
  el.dataset.screen = name;
  screensEl.appendChild(el);
  render[name](el, arg);
  return el;
}
function setRoot(name, arg) {
  closeOverlay();
  screensEl.innerHTML = "";
  stack = [{ name, arg, el: mount(name, arg) }];
  showTabbar(["home", "stations", "me"].includes(name));
  if (["home", "stations", "me"].includes(name)) { tab = name; document.querySelectorAll("#tabbar button").forEach((b) => b.classList.toggle("on", b.dataset.tab === name)); }
  markGuide(name, arg);
}
function push(name, arg, how = "enter") {
  closeOverlay();
  const top = stack.at(-1);
  const el = mount(name, arg);
  el.classList.add(how);
  requestAnimationFrame(() => requestAnimationFrame(() => { el.classList.remove(how); if (how === "enter") top?.el.classList.add("under"); }));
  stack.push({ name, arg, el, how });
  showTabbar(false);
  markGuide(name, arg);
}
function pop() {
  if (stack.length < 2) return;
  const { el, how } = stack.pop();
  const under = stack.at(-1);
  el.classList.add(how === "rise" ? "rise" : "leave");
  under.el.classList.remove("under");
  setTimeout(() => el.remove(), 380);
  showTabbar(["home", "stations", "me"].includes(under.name));
  if (under.name === "home") refreshHome();
  markGuide(under.name, under.arg);
}
function go(target) {
  const [name, arg] = target.split(":");
  if (name === "chat") { setRoot("home"); push("chat", arg); }
  else if (name === "newchat") { setRoot("home"); push("newchat", null, "rise"); }
  else if (name === "station") { setRoot("home"); push("stations"); push("station", arg); }
  else if (name === "stations" || name === "me") { setRoot("home"); push(name); }
  else setRoot(name);
}
function markGuide(name, arg) {
  const key = arg ? `${name}:${arg}` : name;
  document.querySelectorAll(".guide [data-go]").forEach((b) => b.classList.toggle("on", b.dataset.go === key));
}
document.querySelectorAll(".guide [data-go]").forEach((b) => b.addEventListener("click", () => go(b.dataset.go)));
document.querySelectorAll("#tabbar button").forEach((b) => b.addEventListener("click", () => setRoot(b.dataset.tab)));

// ── screens ──────────────────────────────────────────────────────
const render = {};
const sourceIcon = (s) => (s.source === "slack" ? `<i class="i i-slack"></i>` : `<i class="i i-ember"></i>`);

render.signin = (el) => {
  showTabbar(false);
  el.innerHTML = `<div class="signin">
    <img class="hero" src="assets/illus-sign-in.svg" alt="">
    <h1>让 agent 一直在干活</h1>
    <p>登录后，你所在 workspace 的所有 station 和会话都会出现在这里。</p>
    <button class="google"><i></i>用 Google 登录</button>
    <p style="font-size:12px">多个账号可以都登录，随时切换 workspace。</p></div>`;
  $(".google", el).onclick = () => setRoot("home");
};

render.home = (el) => {
  // "我参与的": chats you have written in, whoever started them.
  const shown = sessions.filter((s) => !onlyMine || (s.people ?? []).includes("me"));
  const needs = shown.filter((s) => s.state === "block");
  const running = shown.filter((s) => s.state === "running");
  const rest = shown.filter((s) => !["block", "running"].includes(s.state));
  // The head stays put (you, the workspace, the stations); search scrolls away with the chats.
  el.innerHTML = `<header class="home-head">
    <div class="home-top"><button class="avatar sm me-btn" title="我">左</button><button class="ws-switch"><b>${esc(ws.name)}</b></button><button class="nav-btn st-btn" title="Station"><span class="tab-ico ico-server"></span></button></div>
</header>
    <div class="scroll">
    <div class="search"><i class="i i-search"></i>搜索会话</div>

    ${needs.length ? `<div class="section-h"><b>需要你处理</b><span>${needs.length} 个 agent 在 block</span></div>
    <div class="needs">${needs.map((s) => `<div class="need-card" data-open="${s.id}">
      <div class="need-head">${modelStack(s.models, "badge-block")}<div class="t"><b>${byOther(s)}${esc(s.title)}</b></div><span class="when">${s.when}</span></div>
      <div class="need-q">${esc(s.question)}</div>
      <div class="quick">${s.quick.map((q, i) => `<button class="${i === 0 ? "primary" : ""}" data-quick="${s.id}" data-text="${esc(q)}">${esc(q)}</button>`).join("")}</div></div>`).join("")}</div>` : ""}
    ${running.length ? `<div class="section-h"><b>进行中</b><span>${running.length}</span></div>
    <div>${running.map((s) => `<div class="row" data-open="${s.id}">${modelStack(s.models, "badge-run")}
      <div class="t"><b>${byOther(s)}${esc(s.title)}</b><small class="live-act"><span class="act" data-live="${s.id}">${esc(s.steps[s.step ?? 0])}</span></small></div></div>`).join("")}</div>` : ""}
    <div class="section-h"><b>今天</b></div>
    <div>${rest.map((s) => `<div class="row" data-open="${s.id}">${modelStack(s.models, s.state === "failed" ? "badge-failed" : "")}
      <div class="t"><b class="${s.state === "failed" ? "failed" : ""}">${byOther(s)}${esc(s.title)}</b></div><span class="when">${s.when}</span></div>`).join("")}</div>
    <div class="pad-bottom"></div></div>
    <div class="toolbar">
      <div class="seg home-seg"><button data-mine="0" class="${onlyMine ? "" : "on"}">全部</button><button data-mine="1" class="${onlyMine ? "on" : ""}">我参与的</button></div>
      <button class="fab" title="新对话"><i class="i i-pen"></i></button>
    </div>`;
  el.querySelectorAll("[data-mine]").forEach((b) => (b.onclick = () => { onlyMine = b.dataset.mine === "1"; refreshHome(); }));
  el.querySelectorAll("[data-open]").forEach((n) => n.addEventListener("click", (e) => { if (!e.target.closest("[data-quick]")) push("chat", n.dataset.open); }));
  el.querySelectorAll("[data-quick]").forEach((b) => b.addEventListener("click", (e) => { e.stopPropagation(); answerBlock(byId(b.dataset.quick), b.dataset.text); refreshHome(); }));
  $(".fab", el).onclick = () => push("newchat", null, "rise");
  $(".me-btn", el).onclick = () => push("me");
  $(".st-btn", el).onclick = () => push("stations");
  $(".ws-switch", el).onclick = openWorkspaces;
  $("#tab-badge").textContent = needs.length || "";
};
function refreshHome() { const h = stack.find((x) => x.name === "home"); if (h) { const top = h.el.querySelector(".scroll")?.scrollTop ?? 0; render.home(h.el); h.el.querySelector(".scroll").scrollTop = top; } }

render.chat = (el, id) => {
  const s = byId(id);
  el.innerHTML = `<div class="navbar compact"><button class="nav-back">会话</button>
      <div class="nav-title"><b>${esc(s.title)}</b><small>${sourceIcon(s)}${peopleStack(s.people, 14)}<span class="mini-models">${s.models.map((m) => `<img src="assets/${maker(m)}.svg" alt="">`).join("")}</span></small></div>
      <button class="nav-btn" data-more><i class="i i-more"></i></button></div>
    <div class="scroll"><div class="chat-list"></div></div>
    <div class="composer">
      <div class="composer-extra"></div>
      <div class="composer-bar"><button class="plus"><i class="i i-plus"></i></button>
        <div class="composer-input" contenteditable="true" data-placeholder="给这个会话发消息"></div>
        <button class="send" disabled><i class="i i-up"></i></button></div></div>`;
  $(".nav-back", el).onclick = pop;
  $("[data-more]", el).onclick = () => openChatInfo(s);
  $(".plus", el).onclick = () => openAttach(el);
  const input = $(".composer-input", el), send = $(".send", el);
  input.oninput = () => (send.disabled = !input.textContent.trim() && !el._quote && !el._thumbs);
  send.onclick = () => {
    const text = input.textContent.trim();
    s.messages.push({ mine: true, text: text || "（附件）", quote: el._quote, image: !!el._thumbs });
    input.textContent = ""; el._quote = null; el._thumbs = 0; $(".composer-extra", el).innerHTML = ""; send.disabled = true;
    if (s.state === "block") answerBlock(s, null, true);
    else if (s.state !== "running") startRun(s, ["思考", "读取相关文件", "写回复"], "收到，我先看一下。");
    drawChat(el, s);
  };
  el._session = s;
  drawChat(el, s);
};

function drawChat(el, s) {
  const list = $(".chat-list", el);
  const seen = el._seen ?? s.messages.length;
  list.innerHTML = s.messages.map((m, i) => m.person
    ? `<div class="m${i >= seen ? " new" : ""}" data-i="${i}"><div class="m-head">${peopleStack([m.person], 20)}<b>${people[m.person].name}</b><span>2 分钟前</span></div><div class="m-body">${esc(m.text)}</div></div>`
    : m.mine
    ? `<div class="m mine${i >= seen ? " new" : ""}" data-i="${i}">${m.quote ? `<div class="quote-card"><b>${esc(m.quote.who)}：</b>${esc(m.quote.text)}</div>` : ""}<div class="bubble">${esc(m.text)}</div>${m.image ? `<div class="m-img"></div>` : ""}<span class="m-time">刚刚</span></div>`
    : `<div class="m${i >= seen ? " new" : ""}" data-i="${i}"><div class="m-head" data-hist data-model="${m.model ?? s.model}">${modelLogo(m.model ?? s.model, "xs")}<b>${m.model ?? s.model}</b><span>${m.block ? "block" : ""}</span></div>
       <div class="m-body">${m.html}</div>${m.image ? `<div class="m-img"></div>` : ""}
       ${m.block && s.state === "block" ? `<div class="m-block"><div class="m-block-label"><span class="block-dot"></span>agent 停下来等你决定</div><div class="quick">${s.quick.map((q, j) => `<button class="${j === 0 ? "primary" : ""}" data-q="${esc(q)}">${esc(q)}</button>`).join("")}</div></div>` : ""}</div>`).join("")
    + (s.streaming ? `<div class="m"><div class="m-head" data-hist>${modelLogo(s.model, "xs")}<b>${s.model}</b><span>正在输入</span></div><div class="m-body caret">${esc(s.streaming)}</div></div>` : "")
    // The activity is always last.
    + (s.state === "running" ? activityHtml(s) : "");
  list.querySelectorAll("[data-hist]").forEach((b) => (b.onclick = () => openHistory(s, "history", b.dataset.model || s.model)));
  list.querySelectorAll("[data-q]").forEach((b) => (b.onclick = () => { answerBlock(s, b.dataset.q); drawChat(el, s); }));
  list.querySelectorAll(".m").forEach((m) => longPress(m, () => openMessageMenu(el, s, Number(m.dataset.i), m)));
  el._seen = s.messages.length;
  const scroller = $(".scroll", el);
  scroller.scrollTop = scroller.scrollHeight;
}

function activityHtml(s) {
  const done = s.steps.slice(0, s.step ?? 0), cur = s.steps[s.step ?? 0];
  const rows = [...done.slice(-3).map((t) => `<div class="act-row">${esc(t)}</div>`), `<div class="act-row live">正在${esc(cur)}…</div>`];
  const shift = Math.max(0, rows.length - 3);
  // The whole activity opens the history: it is a glimpse of it.
  return `<div class="m activity-block" data-hist><div class="m-head">${modelLogo(s.model, "xs badge-run")}<b>${s.model}</b><span>工作中 · ${s.elapsed ?? 12}s</span></div>
    <div class="activity-rows"><div style="transform:translateY(${-shift * 22}px)">${rows.join("")}</div></div></div>`;
}

render.newchat = (el) => {
  const pick = { station: stations[0], model: "deepseek-flash", effort: "默认" };
  el.innerHTML = `<div class="navbar compact"><button class="nav-back">取消</button><div class="nav-title"><b>新对话</b></div><span style="width:34px"></span></div>
    <div class="scroll">
      <div class="nc-hero"><img src="assets/illus-new-chat.svg" alt=""><h2>想让 agent 做什么？</h2><p>选好在哪台机器、用什么模型，然后说就行。</p></div>
      <div class="nc-suggest">
        <button data-s="跑一下测试，失败的话看看是哪个">跑一下测试，失败的话看看是哪个<small>常用 · studio</small></button>
        <button data-s="看看这台机器的磁盘和内存">看看这台机器的磁盘和内存<small>常用 · 任意 station</small></button>
        <button data-s="帮我 review 最近一个 PR">帮我 review 最近一个 PR<small>最近用过</small></button>
      </div></div>
    <div class="composer">
      <div class="choosers"></div>
      <div class="composer-bar"><button class="plus"><i class="i i-plus"></i></button>
        <div class="composer-input" contenteditable="true" data-placeholder="做任何事"></div>
        <button class="send" disabled><i class="i i-up"></i></button></div></div>`;
  const chooser = $(".choosers", el);
  const draw = () => {
    chooser.innerHTML = `<button data-c="station"><span class="dot done"></span>${pick.station.name}</button>
      <button data-c="model"><img src="assets/${maker(pick.model)}.svg" alt="">${pick.model}</button>
      <button data-c="effort">思考 ${pick.effort}</button>`;
    chooser.querySelectorAll("[data-c]").forEach((b) => (b.onclick = () => openPicker(b.dataset.c, pick, draw)));
  };
  draw();
  $(".nav-back", el).onclick = pop;
  const input = $(".composer-input", el), send = $(".send", el);
  input.oninput = () => (send.disabled = !input.textContent.trim());
  el.querySelectorAll("[data-s]").forEach((b) => (b.onclick = () => { input.textContent = b.dataset.s; send.disabled = false; input.focus(); }));
  $(".plus", el).onclick = () => openAttach(el);
  send.onclick = () => {
    const s = { id: "new" + Date.now(), title: input.textContent.trim(), station: pick.station.name, source: "ember", model: pick.model, models: [pick.model], people: ["me"], effort: pick.effort === "默认" ? "" : pick.effort, state: "running", when: "进行中",
      messages: [{ mine: true, text: input.textContent.trim() }], history: [["recv", "收到来自 你 的消息", input.textContent.trim()]] };
    sessions.unshift(s);
    startRun(s, ["启动 Claude Code", "思考", "查看工作区", "运行命令", "写回复"], "看了一下：studio 的磁盘还剩 311 GB，内存用了 30 GB / 64 GB，都很宽裕。");
    stack.pop(); el.remove(); setRoot("home"); push("chat", s.id);
  };
};

render.stations = (el) => {
  el.innerHTML = `<div class="scroll"><div class="navbar" style="min-height:0;padding-bottom:0"><button class="nav-back">会话</button></div>
    <div class="large-title"><div class="ws-switch"><small>${esc(ws.name)} · ${stations.filter((s) => s.online).length}/${stations.length} 在线</small><b style="font-size:32px">Station</b></div></div>
    ${stations.map((st) => `<div class="card" data-st="${st.id}"><div class="st-head"><img class="buddy" src="${face(st.online ? (st.agents ? "working" : "idle") : "offline")}" alt="">
      <div class="t"><b>${st.name}</b><small>${st.online ? `${st.host} · ${st.agents ? `${st.agents} 个 agent 在跑` : "空闲"}` : "离线 · 2 小时前"}</small></div><i class="i i-chev"></i></div>
      ${st.online ? `<div class="st-rings">${ring(st.cpu, "CPU")}${ring(st.mem, "内存")}${ring(st.disk, "磁盘")}</div>` : `<div class="st-offline"><img src="assets/illus-station-offline.svg" alt="">这台机器很久没联系 ember 了</div>`}</div>`).join("")}
    <div class="pad-bottom"></div></div>`;
  el.querySelectorAll("[data-st]").forEach((c) => (c.onclick = () => push("station", c.dataset.st)));
  const back = $(".nav-back", el); if (back) back.onclick = pop;
};

render.station = (el, id) => {
  const st = stations.find((s) => s.id === id);
  el.innerHTML = `<div class="navbar compact"><button class="nav-back">Station</button><div class="nav-title"><b>${st.name}</b><small>${st.host}</small></div><span style="width:34px"></span></div>
    <div class="scroll" style="padding-top:12px">
      ${st.online ? `<div class="card"><div class="rings" style="padding:4px 0">${ring(st.cpu, "CPU")}${ring(st.mem, "内存")}${ring(st.disk, "磁盘")}</div><small style="color:var(--muted)">macOS 26.5 · 12 核 · 64 GB · 已运行 88 天</small></div>` : `<div class="card st-offline"><img src="assets/illus-station-offline.svg" alt="">离线：在这台机器上打开 ember 就会重新连上</div>`}
      <div class="section-h" style="padding-left:24px"><b>Profile</b><span>勾选的模型才能用</span></div>
      ${st.profiles.map((p) => `<div class="card"><b>${esc(p.name)}</b><div style="font-size:13px;color:var(--muted)">额度已用 ${p.quota}% · 5 小时窗口</div>
        <div class="model-list">${p.models.map((m) => `<span class="${p.on.includes(m) ? "on" : ""}" data-m="${m}">${p.on.includes(m) ? "✓ " : ""}${m}</span>`).join("")}</div></div>`).join("") || `<div class="card" style="color:var(--muted)">这台机器还没有 Profile。</div>`}
      <div class="section-h" style="padding-left:24px"><b>连接</b></div>
      <div class="list-card"><div class="li"><i class="i i-slack"></i>ember · Acme Slack<small>在线</small></div><div class="li"><i class="i i-ember"></i>ember 对话<small>内置</small></div></div>
      <div class="pad-bottom"></div></div>`;
  $(".nav-back", el).onclick = pop;
  el.querySelectorAll("[data-m]").forEach((sp) => (sp.onclick = () => { sp.classList.toggle("on"); sp.textContent = (sp.classList.contains("on") ? "✓ " : "") + sp.dataset.m; }));
};

render.me = (el) => {
  el.innerHTML = `<div class="scroll"><div class="navbar" style="min-height:0;padding-bottom:0"><button class="nav-back">会话</button></div>
    <div class="large-title"><div class="ws-switch"><small>设置</small><b style="font-size:32px">我</b></div></div>
    <div class="card me-card"><span class="avatar">左</span><div><b>左子健</b><div style="font-size:13px;color:var(--muted)">zuozijian@gmail.com · Google</div></div></div>
    <div class="section-h" style="padding-left:24px"><b>推送</b><span>手机主要用来被叫醒</span></div>
    <div class="list-card">
      <div class="li">agent 进入 block<div class="toggle on"></div></div>
      <div class="li">一轮完成<div class="toggle"></div></div>
      <div class="li">失败或意外停止<div class="toggle on"></div></div>
      <div class="li">锁屏显示进行中的任务<div class="toggle on"></div></div></div>
    <div class="section-h" style="padding-left:24px"><b>账号与 workspace</b></div>
    <div class="list-card">${workspaces.map((w) => `<div class="li">${esc(w.name)}<small>${esc(w.account)}</small></div>`).join("")}<div class="li" style="color:var(--accent)">＋ 登录另一个 Google 账号</div></div>
    <div class="section-h" style="padding-left:24px"><b>外观</b></div>
    <div class="list-card"><div class="li">深色模式<div class="toggle ${dark() ? "on" : ""}" data-dark></div></div></div>
    <div class="list-card"><div class="li" style="color:var(--red)">退出登录</div></div>
    <div class="pad-bottom"></div></div>`;
  el.querySelectorAll(".toggle").forEach((t) => (t.onclick = () => { t.classList.toggle("on"); if ("dark" in t.dataset) toggleTheme(); }));
  const back = $(".nav-back", el); if (back) back.onclick = pop;
};

render.lock = (el) => {
  showTabbar(false);
  const s = byId("zork");
  el.innerHTML = `<div class="lock"><div class="lock-date">9 月 26 日 星期五</div><div class="lock-time">9:41</div>
    <div class="la"><div class="la-head">${modelLogo(s.model, "la-logo")}<div class="t"><b>${esc(s.title)}</b><small data-la-step>正在${esc(s.steps[s.step ?? 0])}</small></div><small style="opacity:.8">studio</small></div>
      <div class="la-bar"><div data-la-bar style="width:${((s.step ?? 0) + 1) / s.steps.length * 100}%"></div></div><div class="la-foot"><span>gpt-6-astra · medium</span><span>已运行 2 分 14 秒</span></div></div>
    <div class="lock-note"><div class="banner-head"><img src="assets/blocked.svg" alt="">ember · studio<span>3 分钟前</span></div><b>staging 告警：需要你决定</b><p>要我把告警规则改成 UTC 并重启 notifier 吗？</p>
      <div class="quick"><button>改吧</button><button>先别</button><button>打开</button></div></div>
    <div class="lock-hint">长按通知可以直接回复 · 上滑解锁</div></div>`;
  el.querySelectorAll(".lock-note .quick button").forEach((b, i) => (b.onclick = () => { if (i === 2) go("chat:staging"); else { answerBlock(byId("staging"), i === 0 ? "改吧，现在重启" : "先别重启"); b.closest(".lock-note").innerHTML = `<p>已回复：${i === 0 ? "改吧，现在重启" : "先别重启"}</p>`; } }));
};

function ring(p, label) {
  const r = 20, c = 2 * Math.PI * r;
  return `<div class="ring"><svg viewBox="0 0 46 46"><circle class="track" cx="23" cy="23" r="${r}"/><circle class="fill ${p > 85 ? "high" : p > 65 ? "warn" : ""}" cx="23" cy="23" r="${r}" stroke-dasharray="${c * p / 100} ${c}"/></svg><b>${p}</b>${label}</div>`;
}

// ── overlays ─────────────────────────────────────────────────────
function closeOverlay() { overlay.querySelectorAll(".sheet").forEach((s) => (s.style.transform = "")); overlay.querySelector(".scrim")?.classList.remove("show"); overlay.querySelector(".menu")?.classList.remove("show"); setTimeout(() => { if (!overlay.querySelector(".sheet.open")) overlay.innerHTML = ""; }, 320); overlay.querySelectorAll(".sheet").forEach((s) => s.classList.remove("open")); document.querySelectorAll(".m.pressed").forEach((m) => m.classList.remove("pressed")); }
function sheet(html, { height = 0.6, draggable = false } = {}) {
  overlay.innerHTML = `<div class="scrim"></div><div class="sheet open" style="height:${height * 100}%">${html}</div>`;
  const scrim = $(".scrim", overlay), sh = $(".sheet", overlay);
  scrim.onclick = closeOverlay;
  requestAnimationFrame(() => { scrim.classList.add("show"); sh.style.transform = "translateY(0)"; });
  if (draggable) dragSheet(sh);
  return sh;
}
// Drag the grabber: snaps to half or full, or closes when pulled down.
function dragSheet(sh) {
  const grab = $(".sheet-grab", sh); let startY = 0, startH = 0, h = 0; const total = device.clientHeight;
  grab.onpointerdown = (e) => { startY = e.clientY; startH = sh.getBoundingClientRect().height; sh.classList.add("dragging"); grab.setPointerCapture(e.pointerId); };
  grab.onpointermove = (e) => { if (!sh.classList.contains("dragging")) return; h = Math.max(120, Math.min(total * 0.94, startH + (startY - e.clientY))); sh.style.height = h + "px"; };
  grab.onpointerup = () => { sh.classList.remove("dragging"); const f = h / total; if (!h) { sh.style.height = sh.style.height === `${total * 0.94}px` ? "55%" : "94%"; return; } if (f < 0.3) closeOverlay(); else sh.style.height = f > 0.72 ? "94%" : "55%"; h = 0; };
}

function openHistory(s, tabName = "history", model = s.model) {
  const sh = sheet(`<div class="sheet-grab"><i></i></div><div class="sheet-head"><span class="hist-title">${modelLogo(model, "xs")}<b>${esc(model)}</b><small>执行历史</small></span><div class="seg"><button data-t="history">步骤</button><button data-t="details">详情</button></div></div><div class="scroll"></div>`, { height: 0.55, draggable: true });
  const body = $(".scroll", sh);
  const show = (t) => {
    sh.querySelectorAll(".seg button").forEach((b) => b.classList.toggle("on", b.dataset.t === t));
    if (t === "history") {
      body.innerHTML = s.history.map(([k, a, b]) => k === "recv" ? `<div class="h-item recv"><small>${esc(a)}</small>${esc(b)}</div>`
        : k === "post" ? `<div class="h-post"><small>${esc(a)}</small><div>${esc(b)}</div></div>` : `<div class="h-item h-group">${esc(a)}</div>`).join("")
        + (s.state === "running" ? `<div class="h-item"><span class="live-act"><span class="act">正在${esc(s.steps[s.step ?? 0])}…</span></span><small>Thinking ${s.elapsed ?? 12}s</small></div>` : "")
        + `<p style="color:var(--subtle);font-size:12px;text-align:center;margin-top:16px">工具调用按它自己的描述显示；展开一组能看到命令和输出</p>`;
    } else {
      const st = stations.find((x) => x.name === s.station) ?? stations[0];
      body.innerHTML = `<div class="group-label">模型</div><dl class="detail-grid"><dt>模型</dt><dd>${model}</dd><dt>思考深度</dt><dd>${s.effort || "默认"}</dd><dt>Profile</dt><dd>${esc(st.profiles[0]?.name ?? "—")}</dd><dt>消耗</dt><dd>152.7K tokens · 缓存 88%</dd></dl>
        <div class="group-label">额度</div><div class="rings">${ring(st.profiles[0]?.quota ?? 0, "5 小时")}${ring(61, "每周")}</div>
        <div class="group-label">Station · ${st.name}</div><div class="rings">${ring(st.cpu, "CPU")}${ring(st.mem, "内存")}${ring(st.disk, "磁盘")}</div>`;
    }
  };
  sh.querySelectorAll(".seg button").forEach((b) => (b.onclick = () => show(b.dataset.t)));
  show(tabName);
}

function openAttach(screen) {
  const sh = sheet(`<div class="sheet-grab"><i></i></div><div class="sheet-head"><b>添加到消息</b></div><div class="attach-grid">
    <button data-a><i class="i i-camera"></i>拍照</button><button data-a><i class="i i-photo"></i>照片</button><button data-a><i class="i i-file"></i>文件</button></div>`, { height: 0.26 });
  sh.querySelectorAll("[data-a]").forEach((b) => (b.onclick = () => {
    screen._thumbs = (screen._thumbs || 0) + 1;
    $(".composer-extra", screen).innerHTML = (screen._quote ? quoteHtml(screen._quote) : "") + `<div class="composer-thumbs">${"<div></div>".repeat(screen._thumbs)}</div>`;
    bindQuoteRemove(screen);
    $(".send", screen).disabled = false; closeOverlay();
  }));
}

function openPicker(kind, pick, done) {
  const items = kind === "station" ? stations.map((s) => ({ v: s, label: s.name, sub: s.online ? `${s.host} · 在线` : "离线", off: !s.online, on: pick.station === s }))
    : kind === "model" ? stations.flatMap((s) => s.profiles).flatMap((p) => p.on).filter((m, i, a) => a.indexOf(m) === i).map((m) => ({ v: m, label: m, sub: m.startsWith("gpt") ? "Codex" : "Claude Code", on: pick.model === m }))
    : ["默认", "low", "medium", "high", "xhigh"].map((e) => ({ v: e, label: e === "默认" ? "运行时默认" : e, on: pick.effort === e }));
  const sh = sheet(`<div class="sheet-grab"><i></i></div><div class="sheet-head"><b>${{ station: "在哪台 station 上跑", model: "用哪个模型", effort: "思考深度" }[kind]}</b></div>
    <div class="pick-list">${items.map((it, i) => `<button data-i="${i}" ${it.off ? "disabled style=opacity:.45" : ""}>${kind === "model" ? modelLogo(it.v) : ""}<span>${esc(it.label)}${it.sub ? `<small>${esc(it.sub)}</small>` : ""}</span>${it.on ? `<i class="i i-check ck"></i>` : ""}</button>`).join("")}</div>
    ${kind === "model" ? `<p style="padding:0 20px 30px;margin:0;font-size:12px;color:var(--muted)">只列出在 Profile 里勾选过的模型；由 station 的账号池挑一个有余量的账号来跑。</p>` : ""}`, { height: kind === "effort" ? 0.48 : 0.5 });
  sh.querySelectorAll("[data-i]").forEach((b) => (b.onclick = () => { const it = items[b.dataset.i]; pick[kind] = it.v; done(); closeOverlay(); }));
}

function openWorkspaces() {
  const sh = sheet(`<div class="sheet-grab"><i></i></div><div class="sheet-head"><b>切换 workspace</b></div><div class="pick-list">
    ${workspaces.map((w, i) => `<button data-w="${i}"><span class="avatar sm" style="background:${["#5B7BB2", "#2F8F5B", "#B9471F"][i]}">${w.name[0]}</span><span>${esc(w.name)}<small>${esc(w.account)} · ${w.stations} 台 station</small></span>${w === ws ? `<i class="i i-check ck"></i>` : ""}</button>`).join("")}
    <button style="color:var(--accent)">＋ 新建 workspace</button></div>`, { height: 0.5 });
  sh.querySelectorAll("[data-w]").forEach((b) => (b.onclick = () => { ws = workspaces[b.dataset.w]; closeOverlay(); refreshHome(); }));
}

/** The chat's own page: who takes part (each agent leads to its history), notifications, actions. */
function openChatInfo(s) {
  const agents = s.models.map((m, i) => ({ m, state: i === 0 ? s.state : "done", station: i === 0 ? s.station : "mac-mini" }));
  const label = { block: "在 block", running: "进行中", done: "空闲", failed: "失败" };
  const sh = sheet(`<div class="sheet-grab"><i></i></div><div class="sheet-head"><b>对话信息</b></div><div class="scroll">
    <div class="group-label">参与的 agent · 点开看它的执行历史</div>
    <div class="info-list">${agents.map((a) => `<button data-agent="${a.m}">${modelLogo(a.m, a.state === "block" ? "badge-block" : a.state === "running" ? "badge-run" : "")}<span><b>${a.m}</b><small>${a.station} · ${label[a.state] ?? a.state}</small></span><i class="i i-chev"></i></button>`).join("")}</div>
    <div class="group-label">参与的人</div>
    <div class="info-list">${s.people.map((id) => `<div class="info-row">${peopleStack([id], 28)}<span><b>${people[id].name}</b>${id === "me" ? "<small>你</small>" : ""}</span></div>`).join("")}</div>
    <div class="group-label">通知</div>
    <div class="info-list"><div class="info-row"><span><b>这个对话的推送</b><small>agent block 时通知我</small></span><div class="toggle on"></div></div></div>
    <div class="info-list" style="margin-top:14px">${s.source === "slack" ? `<div class="info-row"><i class="i i-slack"></i><span><b>在 Slack 中打开</b></span></div>` : ""}<div class="info-row"><span><b>拷贝链接</b></span></div><div class="info-row"><span><b style="color:var(--red)">归档对话</b></span></div></div>
  </div>`, { height: 0.72, draggable: true });
  sh.querySelectorAll("[data-agent]").forEach((b) => (b.onclick = () => openHistory(s, "history", b.dataset.agent)));
  sh.querySelectorAll(".toggle").forEach((t) => (t.onclick = () => t.classList.toggle("on")));
}

// Long-press a message: quote or copy.
function longPress(node, fire) {
  let t;
  node.addEventListener("pointerdown", () => { t = setTimeout(() => { node.classList.add("pressed"); fire(); }, 420); });
  ["pointerup", "pointerleave", "pointercancel"].forEach((e) => node.addEventListener(e, () => clearTimeout(t)));
  node.addEventListener("contextmenu", (e) => { e.preventDefault(); clearTimeout(t); node.classList.add("pressed"); fire(); });
}
function openMessageMenu(screen, s, i, node) {
  const m = s.messages[i]; const text = m.mine || m.person ? m.text : m.html.replace(/<[^>]+>/g, "").trim();
  const r = node.getBoundingClientRect(), d = device.getBoundingClientRect();
  overlay.innerHTML = `<div class="scrim"></div><div class="menu" style="left:${Math.min(r.left - d.left, 190)}px;top:${Math.min(r.bottom - d.top + 6, 640)}px"><button data-act="quote">引用<i class="i i-quote"></i></button><button data-act="copy">拷贝<i class="i i-copy"></i></button></div>`;
  const scrim = $(".scrim", overlay), menu = $(".menu", overlay);
  requestAnimationFrame(() => { scrim.classList.add("show"); menu.classList.add("show"); });
  scrim.onclick = closeOverlay;
  $("[data-act=copy]", overlay).onclick = closeOverlay;
  $("[data-act=quote]", overlay).onclick = () => {
    screen._quote = { who: m.mine ? "你" : m.person ? people[m.person].name : (m.model ?? s.model), text: text.slice(0, 60) + (text.length > 60 ? "…" : "") };
    $(".composer-extra", screen).innerHTML = quoteHtml(screen._quote) + (screen._thumbs ? `<div class="composer-thumbs">${"<div></div>".repeat(screen._thumbs)}</div>` : "");
    bindQuoteRemove(screen);
    $(".send", screen).disabled = false; closeOverlay(); $(".composer-input", screen).focus();
  };
}
const quoteHtml = (q) => `<div class="composer-quote"><i class="i i-quote" style="color:var(--accent)"></i><span><b>${esc(q.who)}：</b>${esc(q.text)}</span><button data-unquote>×</button></div>`;
function bindQuoteRemove(screen) { const b = $("[data-unquote]", screen); if (b) b.onclick = () => { screen._quote = null; b.closest(".composer-quote").remove(); }; }

// ── simulated work ───────────────────────────────────────────────
function answerBlock(s, text, alreadyPosted) {
  if (s.state !== "block") return;
  if (!alreadyPosted && text) s.messages.push({ mine: true, text });
  s.history.push(["recv", "收到来自 你 的消息", text ?? "（你的回复）"]);
  startRun(s, ["思考", "修改告警规则为 UTC", "重启 notifier", "验证推送恢复"], "改好了：告警规则已按 UTC 配置，notifier 重启用了 48 秒，刚才补发的测试通知已经收到。");
}
function startRun(s, steps, reply) {
  Object.assign(s, { state: "running", steps, step: 0, elapsed: 0, reply, when: "进行中" });
}
setInterval(() => {
  for (const s of sessions) {
    if (s.state !== "running") continue;
    s.elapsed = (s.elapsed ?? 12) + 2;
    if (s.streaming !== undefined) {
      const next = s.reply.slice(0, s.streaming.length + 6);
      s.streaming = next;
      if (next.length >= s.reply.length) { s.messages.push({ agent: true, html: `<p>${esc(s.reply)}</p>` }); s.history.push(["post", "发出回复", s.reply]); delete s.streaming; s.state = "done"; s.when = "刚刚"; }
    } else if ((s.step ?? 0) < s.steps.length - 1) {
      s.history.push(["group", `${s.steps[s.step ?? 0]}`]);
      s.step = (s.step ?? 0) + 1;
    } else if (s.reply) s.streaming = "";
    else s.step = Math.max(0, s.steps.length - 3); // the long-running demo sessions loop through their last steps
  }
  const top = stack.at(-1);
  if (top?.name === "chat" && top.el._session) drawChat(top.el, top.el._session);
  if (top?.name === "home") document.querySelectorAll("[data-live]").forEach((n) => { const s = byId(n.dataset.live); if (s?.state === "running") n.textContent = s.steps[s.step ?? 0]; else refreshHome(); });
  if (top?.name === "lock") { const s = byId("zork"); const st = $("[data-la-step]", top.el); if (st) { st.textContent = "正在" + s.steps[s.step ?? 0]; $("[data-la-bar]", top.el).style.width = ((s.step ?? 0) + 1) / s.steps.length * 100 + "%"; } }
}, 2000);

// ── push & theme ─────────────────────────────────────────────────
$("#sim-push").onclick = () => {
  const s = byId("staging");
  if (s.state !== "block") Object.assign(s, { state: "block", when: "刚刚" });
  const b = $("#banner");
  b.innerHTML = `<div class="banner-head"><img src="assets/blocked.svg" alt="">ember · studio<span>现在</span></div><b>staging 告警：需要你决定</b><p>要我把告警规则改成 UTC 并重启 notifier 吗？</p>`;
  b.hidden = false; requestAnimationFrame(() => b.classList.add("show"));
  b.onclick = () => { b.classList.remove("show"); go("chat:staging"); };
  setTimeout(() => b.classList.remove("show"), 5000);
  if (stack.at(-1)?.name === "home") refreshHome();
};
function toggleTheme() {
  device.dataset.theme = dark() ? "light" : "dark";
  document.body.style.setProperty("--page", dark() ? "#2A2B2F" : "#EAE6DF");
  document.body.style.color = dark() ? "#E9E9EA" : "";
  const top = stack.at(-1); if (top) { top.el.innerHTML = ""; render[top.name](top.el, top.arg); }
}
$("#sim-theme").onclick = toggleTheme;

// Keep the zork demo session moving from the start.
Object.assign(byId("zork"), { step: 3, elapsed: 134 });
Object.assign(byId("weekly"), { step: 1, elapsed: 40 });
setRoot("home");
