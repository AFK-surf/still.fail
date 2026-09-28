//! test/admin.test.ts, ported.

use super::*;

#[test]
fn secrets_are_masked_for_the_pages() {
    assert_eq!(mask(""), "");
    assert_eq!(mask("short"), "••••");
    assert_eq!(mask("xoxb-123456789"), "xoxb-…6789");
}
