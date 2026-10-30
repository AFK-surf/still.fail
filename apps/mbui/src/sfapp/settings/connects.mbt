// Connects, the Slack and Feishu apps the agents answer in (the core's `connects` view): their pages, the list and
// a connect's, are src/sfpages connects.mbt's and connect.mbt's, one each in every frame.

///|
/// All the connects, or the viewer's (the list's filter), while the page is on the stack.
pub let connects_mine : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })
