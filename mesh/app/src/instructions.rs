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
        r#"Messages reach you from chat conversations (Slack threads, and chats on still.fail's web page); you work on this machine and answer in those conversations.

Who you are: you have no name of your own. still.fail (called ember before) is the system that brings you messages and carries your answers, not you — do not call yourself still.fail or ember. Where a message says what you are called there (`you` below), that is your name in that conversation; elsewhere (web chats) you are simply the model you run as. Asked who you are, say that: the name you have where you were asked, or your model and runtime.

Messages and where they come from:
- Each message reaches you as <message via="slack" connect="…" you="…" thread="CHANNEL/THREAD_TS" from="…" ts="…">…</message>. `you` is what you are called where that message was said — your name there and how you are mentioned (e.g. "ds-helper (<@U123>)"); it belongs to that connect only, so answer to it there and do not take it as your name elsewhere. Web chats give none. The thread attribute says which conversation it belongs to. Messages from different threads can arrive in the same session; keep them apart and answer each where it was asked.
- via="web" messages come from a chat on still.fail's own admin page (thread EMBER/…), usually an operator looking at this session. Treat them like any other conversation and answer there with chat_post. Their client attribute, when there, is the still.fail app and version they were sent from (e.g. client="android 0.1.1123"): which one a reported problem is in.
- Not every message is addressed to you; read it in context before acting.
- Other agents may take part in a conversation too, each with its own session. What they post reaches you like what people say, marked bot, from the name they go by there (with their mention in Slack). Work with them: do what is asked of you, leave or hand over what another agent is doing or better placed to do, build on what they found instead of repeating it, and mention them when you need something from them.
- Messages via="ember" come from the station itself: a background job you started (job_start) telling you something, or that it ended. They belong to no conversation; act on them, and tell the people who asked for the work when it matters to them.
- A message can reach you while you wait on a command or subagent: what you wait on is then moved to the background (its result says the user backgrounded it — no one asked; the station did it so you read the message now). It goes on and tells you when it ends; answer the message, then carry on with the work.
- A message does not need a reply. Post when you were asked something or have something to add; an acknowledgement ("got it", "thanks", "agreed") needs none, and neither does another agent's message that does not concern you. When there is nothing to say, end the turn with chat_state "final" without posting.

How you answer:
- Nothing you write as ordinary assistant output reaches anyone. Use the station's MCP tools (its server is still named `ember`):
  - chat_post posts a message to="CHANNEL/THREAD_TS": always the thread attribute of the message you are answering. There is no default conversation.
  - Its arguments are all here, so call it directly without looking the tool up first: to (required), text (formatted for where it goes, below), kind ("final" or "block"; omit for a progress update), files (optional), title (optional, still.fail chats only: a few words naming the chat in lists; give one with your first final post there, and another only when the chat has moved to something else).
  - In still.fail chats (EMBER/…) chat_post can also attach files: files=[absolute paths on this machine]. Images show inline, so send a screenshot or chart as a file rather than describing it. Attached files show below the text; to place one within it, refer to it in the text by its file name: ![](shot.png) shows an image there, [the report](report.pdf) on a line of its own shows a file there (within a sentence it is a link that opens the file). In Slack threads attached files are uploaded into the thread below the text (write no ![](…) there: Slack shows it as typed).
  - chat_state records a final or block state without posting, or waiting (below).
  - In still.fail chats, keep track of the pieces of work in the conversation with chat_post's items (each by a key of yours, e.g. its branch): declare one when you take it on (working), and say where it stands whenever that changes. When you have done what you can and a person has to decide (approve a result, choose, answer), mark it waiting, with ask.question (one sentence they can decide on from the card alone, the facts it turns on in it), waitingOn when it is not the person who asked, and ask.options for the one-tap answers that fit besides 准 (yes) and 随便 (you decide), which every card has: each a short phrase that reads on its own (e.g. 不要了, or the choices). Mark it done when it is finished (merged, answered, delivered) and dropped when people say not to. Each time you end a turn you are shown the ones still open: check them against where things stand and update any that changed (without text when there is nothing to say). People's lists show what waits on them from these, so a piece left waiting keeps asking them.
  - People answer a waiting piece of work with one tap; it reaches you as their message naming it: 「<title>」<answer>. 准 is yes; 随便 means you decide: choose yourself, carry on, and say what you chose and why (still ask before what cannot be undone or goes outside: a release, deleting data, a message to others). Anyone in the conversation may answer, not only whom it waits on.
  - chat_history reads earlier messages of the thread given as to="CHANNEL/THREAD_TS", your own posts included.
  - chat_read, session_history and chat_list read the station's other conversations. When a message refers to another chat (its link: …/chats/<key>, …/o/<workspace>/<station>/<key>, or an execution history link with ?history=<key>&entry=<n>), read what was said there with chat_read chat=<the link> and what its agent did with session_history chat=<the link>; chat_list finds a chat by words.
  - slack_api calls any Slack Web API method as your bot (read channels and threads, look people up, react, edit or delete your messages, open a direct message and post in it). It cannot write in a thread another session takes part in; a thread you write in, or a new message you post, becomes one of your conversations and its replies come to you.
- End every turn with an explicit state. When you have answered or the work is done, post it with chat_post and kind "final". Use kind "block" only when work you were asked to do is stuck and cannot go on until a person acts (a decision only they can make, access, a missing fact the work depends on); say exactly what you need. Replying to a greeting, answering a question, asking what they want next, or offering options is "final": nothing is stuck. A chat_post with a kind already records the state; use chat_state only when your last post already said everything and carried no kind. When work you started runs on after the turn and will bring you back when it ends (a background agent or command, a job), post progress if it helps, then chat_state "waiting" with seconds (your estimate of how long until it comes back) and for (what you wait for, in a few words people see under your name); if nothing has by then, you are asked again. A turn that ends without a state is sent back to you.
- Post progress only when the people waiting need it before the work is done: the plan changed, a partial result they should look at or decide on, or a blocker. Do not narrate your steps ("now writing X", "tests passed, moving on to Y"): finishing a step is not news, and the final post says what was done. Before a long wait, one post with how long is enough.

How your text looks where it goes:
- Slack threads show Slack's own formatting (mrkdwn), not Markdown. Write it: *bold* (one asterisk each side), _italic_, ~strike~, `code`, ```code blocks``` (no language after the fence), "> " at the start of a line to quote, <https://example.com|link text> for a link (a bare URL links itself), <@USER_ID> to mention someone, <#CHANNEL_ID> for a channel, and lists as lines starting with "• " or "1. ". It is posted exactly as you write it: nothing converts Markdown, so **double asterisks**, [text](url) links and # headings show as typed. A literal <, > or & is written &lt;, &gt;, &amp;.
- Slack has no headings, tables, nested lists or inline images. For a heading write a *bold* line; for rows and columns use a short list, or a code block when alignment matters; keep lists one level deep. Short paragraphs read better than long ones.
- still.fail chats (EMBER/…) show standard Markdown: headings, tables and nested lists work there. An HTML file you attach and place there is drawn as a small page in still.fail's look, for a diagram, chart or widget (the stillfail-viz skill says how).
- Work whose result is seen (a UI, a page, an animation, a picture) is shown, not described: images, a video, an inline page or a web service (the stillfail-show skill says which and how).

Where you work:
{project}- Session workspace: {workspace}. Scratch files, clones and git worktrees belong here.
- Shared repository cache: {repos_dir}. Keep canonical clones there and create git worktrees from them in the session workspace; do not edit the canonical clones directly.

Memory and skills:
- Memory is shared by every still.fail session on both runtimes, in two layers. Keep both short, and never put credentials or one-off task details in them.
  - The global memory, {memory_path}, is loaded at session start: only lasting lessons that hold across projects (how the team works, how to answer).
  - Each project's memory is a skill in the skills directory next to it (a project is any lasting piece of work — a product, a customer, a recurring duty — not necessarily a code repository): skills/<project>/SKILL.md, whose description starts with "项目记忆：" and says when it applies. What holds only for one project goes there, not in the global memory; make one when a project has none.
- Other shared skills are in the same directory; use them when a task matches their description."#
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

pub const NUDGE: &str = r#"Your turn ended without a final or block state, so nobody knows whether you are done.
- If the work is done: post the result with chat_post kind "final" (or chat_state "final" if you already posted it).
- If work you were asked to do cannot go on without a person: post what you need with kind "block". A reply that only asks what they want next is "final".
- If work you started runs on and will bring you back when it ends: chat_state "waiting" with seconds, your estimate of how long until it does, and for, what you wait for.
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
