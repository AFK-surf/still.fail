//! What changed in how agents work, told to sessions that began before it (or whose process was handed over by an
//! update and kept its old instructions and tool list): each turn, the notes newer than the last one the session was
//! told come before its messages, once. A change to the instructions or the tools that older sessions must follow adds
//! a note here, with the next number; a new session is told none (its instructions are today's).

/// The notes, oldest first, each with its number (counting up from 1, never reused).
pub const NOTES: &[(i64, &str)] = &[
    (
        1,
        "How a turn ends changed: say it with kind, and say why.\n\
         - all_done (with done): nothing in the chat is left unfinished; done names the evidence (merged where, released, who confirmed, what was answered). Bare words like 做完了 are refused.\n\
         - need_human (with need): a person has to give, do, check or decide something; need says what, in one sentence. Waiting on a person is always need_human, never waiting.\n\
         - waiting (with for, chat_state only): only work you started that brings you back by itself (CI, a build, a job).\n\
         - final, block and need_help are still taken; use the words above.\n\
         Any of them may take about: the ts of the message the state is about.\n\
         A message may carry a card, whatever the turn's kind: chat_post card {\"type\": \"options\", \"options\": [{\"label\", \"detail\", \"recommended\"}]} for a choice, or {\"type\": \"text\", \"placeholder\"} for something to type; then end the turn need_human. These parameters work even where your tool list does not show them: pass them anyway.",
    ),
];

/// The latest note's number: what a session that knows everything has been told.
pub fn latest() -> i64 {
    NOTES.last().map(|(n, _)| *n).unwrap_or(0)
}

/// The notes a session that was told up to `told` has yet to hear, as one block before its messages; empty when none.
pub fn untold(told: i64) -> String {
    let notes: Vec<&str> = NOTES.iter().filter(|(n, _)| *n > told).map(|(_, note)| *note).collect();
    if notes.is_empty() {
        return String::new();
    }
    format!("[still.fail changed how you work since this session began; follow this from now on]\n{}", notes.join("\n\n"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_session_hears_only_what_it_was_not_told() {
        assert!(untold(latest()).is_empty());
        let all = untold(0);
        assert!(all.starts_with("[still.fail changed how you work") && all.contains("need_human"), "{all}");
        let numbers: Vec<i64> = NOTES.iter().map(|(n, _)| *n).collect();
        assert!(numbers.windows(2).all(|w| w[1] == w[0] + 1) && numbers.first() == Some(&1), "numbered 1, 2, 3…: {numbers:?}");
    }
}
