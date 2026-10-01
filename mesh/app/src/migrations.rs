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
    (5, "People can close a card with 无需处理: its need_human wait ends without a reply or waking the agent. Do not reopen that question unless they ask."),
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
