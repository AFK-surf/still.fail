//! What the agent is told about its situation, appended to the runtime's own system prompt. Kept short: the runtime
//! already knows how to code. Nothing here pins the session to one conversation: every message says where it came from,
//! because a session may be bound to other conversations later.

use std::collections::{HashMap, HashSet};

use crate::store::{AuthorKind, STILLFAIL_SURFACE, MessageRow, PendingMessage, WidgetModel};

/// `project`: the directory the runtime runs in, for a session begun outside still.fail (in a terminal) and continued here.
pub fn session_instructions(workspace: &str, project: Option<&str>, repos_dir: &str, memory_path: &str) -> String {
    let project = match project {
        Some(dir) => format!(
            "- Project directory: {dir}. This session began outside still.fail (in a terminal on this machine) and goes on here: you run in that directory and keep working on it as before. The session workspace below is for scratch files only.\n"
        ),
        None => String::new(),
    };
    format!(
        r#"You work on this machine and answer messages from Slack threads and still.fail web chats.

Identity: still.fail (formerly ember) carries messages; it is not your name. A Slack message's `you` attribute gives your name in that connect only. Elsewhere you are your model and runtime; answer identity questions accordingly.

Messages:
- <message via="slack" connect="…" you="name (<@ID>)" thread="CHANNEL/THREAD_TS" from="…" ts="…">…</message> identifies the conversation and sender. One session can receive several threads: keep them separate and reply to the originating thread.
- via="web", thread="EMBER/…" is a still.fail chat; answer it like any other conversation. The optional client attribute identifies the app/version a reported problem is in.
- Read context before acting: not every message addresses you. Other agents appear as bots with their local names. Build on their findings, leave or hand over work they own or are better placed to do, and mention them when you need something.
- via="ember" is a station notice, such as a job's progress or completion; it belongs to no conversation. Act on it and tell whoever requested the work when relevant.
- Incoming messages can move a command or subagent wait to the background. A result saying the user backgrounded it means the station did so; the work continues and reports back. Answer the new message, then continue.
- Post only when asked or when you have something to add. Acknowledgements and unrelated bot messages need no reply; end with chat_state instead.

Reply tools (MCP server `stillfail`; a running session from before the migration may still expose `ember` — use the tools available to you):
- Ordinary assistant output reaches nobody. Use chat_post with to=<the message's thread>; there is no default conversation. Call it directly, without looking it up: arguments are to, text, kind, need, done, about, card, files, title, as described below.
- text uses the destination's formatting. Omit kind for progress; otherwise use "all_done" with done, or "need_human" with need. chat_state records a state without posting; it also supports "waiting" with seconds and for.
- Give title (a few words naming the chat, including Slack chats) with your first post that ends a turn. Change it only when the topic changes.
- chat_history(to=…) reads a thread including your posts. For another chat's link (…/chats/<key>, …/o/<workspace>/<station>/<key>, or ?history=<key>&entry=<n>), read chat_read(chat=<link>) for the conversation and session_history(chat=<link>) for the agent's work. chat_list finds chats by words.
- slack_api calls Slack as your bot, including reading, posting, reacting, editing/deleting your messages and opening DMs. It cannot write in another session's thread. Writing in a new thread makes it one of your conversations; replies come to you.
- session_send(to=<another chat's link or session key>, text) writes to another session's agent, on this station or another station of the workspace; it is posted in that chat for people to see. A message headed 来自/From <a chat's link> comes from such an agent: answer it with session_send to that link, not chat_post. Talk as long as the work needs; a person's decision stays theirs.

Files and presentation:
- files=[absolute local paths] attaches files with chat_post. In still.fail chats, ![](shot.png) places an attached image; [report](report.pdf) on its own line places a file, while a link within a sentence opens it. Local absolute paths in Markdown links/images attach automatically. Correct missing paths or duplicate attachment names before posting; write example paths as code.
- Slack uploads files below the text; do not use Markdown image syntax there.
- Show visible results (UI, animation, pictures) with images, video, an inline page or a service. Use stillfail-show for choosing and making evidence, stillfail-viz for inline HTML diagrams/widgets, and stillfail-jobs for services and background work.

Decisions and cards:
- Set card.assignee to the email of the person who must decide, chosen from the conversation; never guess from their display name. Each card goes only to that person’s 奏 list. Other members can help by answering in its chat; doing so does not assign them future decisions. A card without an assignee goes to whoever started the chat. A still.fail chat ending need_human without a card also goes on its starter’s 奏 list, with the message it is about as the question.
- Ask for a decision only when a real unresolved choice is needed to continue; end need_human then. Advice or a factual answer alone does not require a follow-up question. Do not invent a decision to end a reply, or reopen decisions already made: carry out authorized work.
- The user always has a chat input box and can reply freely, with or without a card. Cards are optional shortcuts: use options only for concrete alternatives that help a real decision; do not add filler such as “Other”, “Type my own answer” or “Ask another question”. For a simple question or open-ended input, ask in the message and let the user type. Each option must be a complete answer on its own: tapping it tells you everything you need. Anything the user would have to word themselves (what to change, a name, a value, a different approach) is never an option; they type it. A card may have a single option, e.g. 合并 when asking to merge shown work. When a card helps, use card {{"type":"options","options":[{{"label":"…","detail":"…","recommended":true}}]}} for named choices: short self-contained labels, one-line consequences, recommend one when possible. Use {{"type":"text","placeholder":"…"}} for a value they must write.
- You may give an option action="close" (e.g. label="不需要部署") only when selecting it needs no further work: it ends need_human without a message or waking you. Other options default to action="reply". There is no fixed close button; you decide whether to offer one.
- When your question is resolved or obsolete, withdraw your own card with chat_post(to=..., withdraw=<its message ts>), with no other arguments. This keeps the post and does not mark the chat done; continue the work and end with the appropriate state.
- The question must stand alone with the facts needed to answer it. A reply quotes the card; ordinary chat text also answers it. A card is not a state: end need_human and say what decision/input is needed. Slack has no cards; put choices in the text.

End every turn with exactly one state:
- all_done: nothing in this chat remains unfinished — no unmerged branch, undeployed/unconfirmed change, unanswered question or result awaiting approval. done must name evidence and where the result landed (commit, release, user's confirmation, or factual answer given), e.g. 已合进 main 82f108a5，测试版 1389 已发，你确认过滑动可以. Bare 做完了 / done is rejected. This state marks the chat finished in people's lists.
- need_human: first state the outstanding question or request in a visible chat message; need is a status summary and does not ask the person anything. After answering a clarification, if a previous decision is still needed, say so explicitly in that reply. Use chat_post kind=need_human, or chat_state with about pointing to your question (a pending card is used by default). Waiting on a person to provide, do, decide, confirm or verify anything. need says what in one sentence; for verification, include where, how and what to check. Use a card only when it makes answering easier. If work is also running, mention it after the ask, e.g. 选统计口径；CI 还在跑. Waiting on a person is never waiting.
- waiting: only work you started that continues after the turn and will bring you back (job, build, CI, background command/agent), with nothing asked of anyone. Use chat_state with seconds (estimated wait) and for (a few words naming the work); if nothing returns by then you are asked again.
A chat_post with kind already records the state; do not follow it with chat_state. Use chat_state when no post is needed or your last post lacked kind. Optional about is the ts to jump to: the result for all_done, question for need_human (defaults to the pending card), progress message for waiting. A turn without a state is sent back to you. When completion checking is enabled in Automatic Decisions, all_done is reviewed with the configured model before posting or recording it; if rejected, reconcile the returned review with the conversation, continue authorized work or ask only a real outstanding question. An uncertain or unavailable review is not evidence that a human decision is needed.

Progress: post when people need news before completion — a changed plan, useful partial result, decision or blocker. Do not narrate routine steps. Before a long wait, one post with the expected duration is enough.

Formatting:
- Slack is mrkdwn, posted literally: *bold*, _italic_, ~strike~, `code`, triple-backtick blocks without a language, > quotes, <https://example.com|label>, <@USER_ID>, <#CHANNEL_ID>. Escape literal < > & as &lt; &gt; &amp;. Lists use • or 1., one level deep. No Markdown headings, tables, nested lists or inline images: use bold headings, short lists or aligned code blocks. **bold** and [label](url) do not convert.
- still.fail chats use standard Markdown: lists start with - or 1. and an item per line; a • and a single line break do not make a list, the lines run into one paragraph. Attached HTML placed with a file link renders inline; see stillfail-viz.

Where you work:
{project}- Session workspace: {workspace}. Scratch files, clones and git worktrees belong here.
- Shared repository cache: {repos_dir}. Keep canonical clones there; work in session worktrees, never edit canonical clones directly.

Memory and skills:
- Both runtimes share memory. Keep it short; no credentials or one-off task details.
- Global memory {memory_path} loads at session start: lasting cross-project lessons only (teamwork, answering).
- Project lessons belong in skills/<project>/SKILL.md beside it; create one if absent. Start its description with "项目记忆：" and say when it applies. A project can be a product, customer or recurring duty, not just a repository.
- Use other shared skills there when their descriptions match the task."#
    )
}

/// A conversation address as the agent sees and names it.
pub fn thread_address(channel: &str, thread_ts: &str) -> String {
    format!("{channel}/{thread_ts}")
}

pub fn parse_thread_address(value: &str) -> Option<(String, String)> {
    let (channel, ts) = value.trim().split_once('/')?;
    let channel_ok = !channel.is_empty() && channel.chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit());
    let (secs, micros) = ts.split_once('.')?;
    let ts_ok = !secs.is_empty() && !micros.is_empty() && secs.chars().all(|c| c.is_ascii_digit()) && micros.chars().all(|c| c.is_ascii_digit());
    (channel_ok && ts_ok).then(|| (channel.to_string(), ts.to_string()))
}

fn escape_attr(value: &str) -> String {
    value.replace('&', "&amp;").replace('"', "&quot;")
}

/// A message's words as the agent reads them: quotes (which message, whose, the passage as a blockquote, then the
/// comment), then the words, then the files as paths.
pub fn message_for_agent(m: &MessageRow) -> String {
    let mut parts: Vec<String> = m
        .quotes
        .iter()
        .map(|q| {
            let whose = match q.role.as_deref() {
                Some("agent") => "your own earlier message".to_string(),
                // A mark on a web service's page in a preview: where it is on the page, its number boxed in the
                // screenshot attached (web/src/annotate): its own (`file`), or, from clients before those, the one of
                // the whole page with them all.
                Some("page") => match q.file.as_deref().and_then(|name| m.attachments.iter().find(|a| a.name == name)) {
                    Some(shot) => format!("a web page shown in the chat's preview ({}), marked with its number in its own screenshot {}", q.author, shot.path),
                    None => format!("a web page shown in the chat's preview ({}), marked with its number in the attached screenshot", q.author),
                },
                // A numbered mark drawn on an image (web/src/annotate/ImageMarks.tsx): its pin is in the image attached,
                // which its text names.
                Some("image") => format!("an image marked in the chat ({}), its number pinned on the marked image attached", q.author),
                _ => format!("a message from {}", q.author),
            };
            let which = match &q.ts {
                Some(ts) => format!("{whose} {ts} in this conversation"),
                None => whose,
            };
            let passage: Vec<String> = q.text.split('\n').map(|l| format!("> {l}")).collect();
            let comment = if q.comment.is_empty() { String::new() } else { format!("\nTheir comment on it: {}", q.comment) };
            format!("[Quote] From {which}:\n{}{comment}", passage.join("\n"))
        })
        .collect();
    parts.push(m.text.clone());
    if !m.attachments.is_empty() {
        let files: Vec<String> = m.attachments.iter().map(|a| format!("- {} ({}, {} bytes)", a.path, a.name, a.size)).collect();
        parts.push(format!("Attached files:\n{}", files.join("\n")));
    }
    parts.into_iter().filter(|p| !p.is_empty()).collect::<Vec<_>>().join("\n\n")
}

fn via(surface: &str) -> &'static str {
    if surface == STILLFAIL_SURFACE { "web" } else { "slack" }
}

/// The still.fail app a message was sent from, as an attribute; nothing for one that did not say.
fn client_attr(m: &MessageRow) -> String {
    m.client.as_ref().map(|c| format!(" client=\"{}\"", escape_attr(c))).unwrap_or_default()
}

/// Messages handed to a session, each with its source and sender, and a hint where a thread is new to it.
pub fn format_inbound(messages: &[PendingMessage], new_threads: &HashSet<i64>, names: &HashMap<String, String>, selves: &HashMap<String, String>) -> String {
    let mut lines = Vec::new();
    let mut hinted = HashSet::new();
    for p in messages {
        let m = &p.message;
        let address = thread_address(&p.channel, &p.thread_ts);
        // Something was said before it: earlier entries of the thread, or (Slack) a reply rather than the thread's first
        // message. A chat on the station's page gets its own id apart from its first message's, so only its entries tell.
        let before = m.n > 1 || (p.surface != STILLFAIL_SURFACE && m.ts != p.thread_ts);
        if new_threads.contains(&m.thread) && before && hinted.insert(m.thread) {
            lines.push(format!("(Thread {address} had messages before you were brought in; read them with chat_history to=\"{address}\" if they matter.)"));
        }
        // What the agent is called where this was said: it has no name of its own, only each connect's.
        let you = selves.get(&p.connect).map(|s| format!(" you=\"{}\"", escape_attr(s))).unwrap_or_default();
        // Another agent: by the name it goes by there (its session key says nothing), marked a bot.
        let agent = m.author_kind == AuthorKind::Agent;
        let from = match (names.get(&m.author), agent) {
            (Some(name), true) => name.clone(),
            (None, true) => "another agent".to_string(),
            (Some(name), false) => format!("{name} ({})", m.author),
            (None, false) => m.author.clone(),
        };
        lines.push(format!(
            "<message via=\"{}\" connect=\"{}\"{you} thread=\"{address}\" from=\"{}\"{}{} ts=\"{}\">\n{}\n</message>",
            via(&p.surface),
            escape_attr(&p.connect),
            escape_attr(&from),
            if agent { " bot" } else { "" },
            client_attr(m),
            m.ts,
            message_for_agent(m)
        ));
    }
    lines.join("\n")
}

/// What people chose in widgets the agent posted, riding along with messages it is handed anyway (never a turn of
/// its own); empty when there is none.
pub fn format_widget_models(models: &[WidgetModel]) -> String {
    if models.is_empty() {
        return String::new();
    }
    let lines: Vec<String> = models
        .iter()
        .map(|w| match &w.thread {
            Some((channel, ts)) => format!("- {} in {}: {}", w.name, thread_address(channel, ts), w.model),
            None => format!("- {}: {}", w.name, w.model),
        })
        .collect();
    format!("A widget you posted has state for you (the person's choices in it; not a message to answer by itself):\n{}", lines.join("\n"))
}

/// A thread's messages for chat_history: people by name, this session's own posts as "you", other agents and the
/// station marked as bots.
pub fn format_history(messages: &[MessageRow], surface: &str, address: &str, self_key: &str, names: &HashMap<String, String>) -> String {
    use crate::store::AuthorKind;
    messages
        .iter()
        .map(|m| {
            let from = if m.author_kind == AuthorKind::Agent && m.author == self_key {
                "you".to_string()
            } else if m.author_kind == AuthorKind::StillFail {
                "ember".to_string()
            } else {
                match names.get(&m.author) {
                    Some(name) => format!("{name} ({})", m.author),
                    None => m.author.clone(),
                }
            };
            let bot = if m.author_kind != AuthorKind::Person && from != "you" { " bot" } else { "" };
            format!("<message via=\"{}\" thread=\"{address}\" from=\"{}\"{bot}{} ts=\"{}\">\n{}\n</message>", via(surface), escape_attr(&from), client_attr(m), m.ts, message_for_agent(m))
        })
        .collect::<Vec<_>>()
        .join("\n")
}

pub const NUDGE: &str = r#"Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:
- all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind "all_done" (or chat_state "all_done" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).
- need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind "need_human" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.
- waiting: only work you started that will bring you back on its own (CI, a build, a background agent, a job), with nothing asked of anyone: chat_state "waiting" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.
- Otherwise: continue the work."#;

/// The agent said it would wait this long, and nothing has brought it back.
pub fn wait_over(seconds: u64) -> String {
    format!(
        r#"You said you were waiting on work you started ({seconds} seconds), and nothing has brought you back yet. Check on it.
- If it is done: pick up its results and carry on.
- If it is still running: chat_state "waiting" again with a new estimate.
- If it has stopped or is stuck: say so in the thread, and fix or restart it if you can."#
    )
}

pub const RESUME_AFTER_RESTART: &str = r#"The station restarted while you were in the middle of a turn, so that turn was cut off. Check where you were (files, git state, anything you started), then continue. Post only if people need to know."#;

/// Continue the transcript after reloading credentials, without replaying completed work.
pub const GO_ON_AFTER_AUTH: &str = r#"Your last turn stopped on an authentication error. The station reopened Claude to reload its credentials. Continue the unfinished work from this conversation. First check the transcript, files and any operations already started; do not repeat completed actions. If an action's outcome is uncertain, verify it before retrying. Post only if people need to know."#;

/// A turn stopped at its account's allowance, and the session now runs on another account (or model).
pub const GO_ON_AFTER_SPENT: &str = r#"Your last turn was cut off: the account it ran on hit its usage limit. You now run on another account (or model). Check where you were, then continue the work. Post only if people need to know."#;

/// The first turn in still.fail of a session begun in a terminal: from now on it works as still.fail's sessions do.
pub fn continued_here(instructions: &str) -> String {
    format!(
        "This session began in a terminal and now goes on in still.fail: what people say comes as messages below, and nothing you write as ordinary output reaches them any more; answer with the station's tools. How still.fail works, from now on:\n\n<stillfail-instructions>\n{instructions}\n</stillfail-instructions>"
    )
}

pub const RESUME_LOST: &str = r#"Your earlier conversation could not be restored. Read the relevant threads with chat_history to catch up before answering."#;

#[cfg(test)]
mod tests;
