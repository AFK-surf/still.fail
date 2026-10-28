///|
/// The system's prompt begun, its reason in it (person.m).
#borrow(reason)
extern "C" fn ask_person(reason : Bytes) -> Unit = "mb_sffix_ask_person"

///|
/// How the prompt went: 0 not yet, 1 yes, 2 no (person.m).
extern "C" fn person_answered() -> Int = "mb_sffix_person_answered"

///|
/// The system's prompt readied (person.m).
extern "C" fn person_ready() -> Unit = "mb_sffix_person_ready"

///|
/// A told story's vault unlocked as on a real device: the system's prompt (sffixture's story_ask_person).
fn ask_person_setup() -> Unit {
  person_ready()
  @sffixture.story_ask_person.val = Some((fn(reason) { ask_person(@utf8.encode(reason)) }, fn() { person_answered() }))
}
