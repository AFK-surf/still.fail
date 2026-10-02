//! What changed in how agents work, told to sessions that began before it (or whose process was handed over by an
//! update and kept its old instructions and tool list): each turn, the notes newer than the last one the session was
//! told come before its messages, once, with where today's whole instructions are to read. A note only names what
//! changed, in a sentence or two: the agent reads the rest when it needs it. A change to the instructions or the tools
//! that older sessions must follow adds a note here, with the next number; a new session is told none.

/// The notes, oldest first, each with its number (counting up from 1, never reused).
pub const NOTES: &[(i64, &str)] = &[
    (1, "How a turn ends: all_done now needs done (the evidence nothing is left), a turn waiting on a person is need_human (with need), and waiting is only for your own work that brings you back (with for). A message can carry a card (options, or a field to type in)."),
    (2, "In still.fail chats, chat_post automatically attaches local files named by inline Markdown links or images. Invalid local paths and conflicting attachment names are rejected before posting; correct them or write paths as code when they are only examples."),
    (3, "After giving advice, a recommendation or proposed options, ask for the user’s decision and end with need_human, not all_done; include an answer card in still.fail chats. Do not reopen decisions already made or ask again before doing authorized work."),
    (4, "Station instructions and built-in skill wording are shorter; the same routing, decision, completion and safety rules still apply. Use the current instructions file and skill files when you need details."),
    (5, "Options may specify action=close to end need_human without a reply or waking you; default is reply. Offer this only when that choice needs no further work; there is no fixed close button."),
    (6, "Set card.assignee to the decision maker’s email. Only that person sees the card in 奏; anyone may still answer in the chat. Legacy unassigned cards remain in the chat, labelled unassigned."),
    (7, "chat_post now accepts only to + withdraw (your question’s message ts) to remove your own resolved or obsolete answer card. It preserves the post and does not mark work complete; continue and record the appropriate ending state."),
    (8, "Users always have a chat input box; answer cards are optional shortcuts for useful concrete choices, not required for every question. Do not add filler options or invent a follow-up decision after an answer or advice; use need_human only for a real outstanding need."),
    (9, "need_human must refer to a visible outstanding question: chat_state requires about or a pending card; alternatively ask with chat_post kind=need_human. After answering a clarification, explicitly say if an earlier decision is still needed; do not invent new questions, and cards remain optional."),
    (10, "Each answer option must be complete on its own; anything the user would word themselves (what to change, a name, a value, a different approach) is never an option, they type it. A card may have a single option, e.g. 合并 when asking to merge shown work."),
    (11, "New runtime processes expose MCP tools under stillfail (mcp__stillfail__…). A handed-over process may still expose ember: use its available tools until that process restarts. Historical transcripts and old tools remain readable."),
    (12, "New tool adb_devices: Android phones people shared with this station from the still.fail app, each reachable with `adb -s 127.0.0.1:<port>`; it also gives the link that opens this station's 共享调试 in a person's app, to ask for one."),
];

/// The latest note's number: what a session that knows everything has been told.
pub fn latest() -> i64 {
    NOTES.last().map(|(n, _)| *n).unwrap_or(0)
}

/// The notes a session that was told up to `told` has yet to hear, as one block before its messages, and where today's
/// whole instructions are (`full`); empty when there are none.
pub fn untold(told: i64, full: &str) -> String {
    let notes: Vec<String> = NOTES.iter().filter(|(n, _)| *n > told).map(|(_, note)| format!("- {note}")).collect();
    if notes.is_empty() {
        return String::new();
    }
    format!(
        "[still.fail changed how you work since this session began]\n{}\nToday's whole instructions, tool parameters included, are in {full}: read them when you need the details (your tool list may not show the new parameters; pass them anyway).",
        notes.join("\n")
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_session_hears_only_what_it_was_not_told() {
        assert!(untold(latest(), "/w/i.md").is_empty());
        let all = untold(0, "/w/i.md");
        assert!(all.starts_with("[still.fail changed how you work") && all.contains("need_human") && all.contains("/w/i.md"), "{all}");
        assert!(NOTES.iter().all(|(_, note)| note.chars().count() < 400), "a note names what changed, no more");
        let numbers: Vec<i64> = NOTES.iter().map(|(n, _)| *n).collect();
        assert!(numbers.windows(2).all(|w| w[1] == w[0] + 1) && numbers.first() == Some(&1), "numbered 1, 2, 3…: {numbers:?}");
    }
}
