//! The name the product goes by in what the core says to people: still.fail, or youdid.wtf on the test channel
//! (still.fail's dual: the beta apps, and the web on the test channel's host). Set once as the core starts, from its
//! host ([`crate::Host::test_channel`]); every UI text the core makes that names the product takes it from [`name`].
//! Only words for people: wire names, identifiers and links keep still.fail's.

use std::cell::Cell;

/// The released channel's name.
pub const STABLE: &str = "still.fail";
/// The test channel's.
pub const TEST: &str = "youdid.wtf";

thread_local! {
    // The core runs on one thread (the web's worker, the native host's own thread), so its channel is that thread's.
    static TEST_CHANNEL: Cell<bool> = const { Cell::new(false) };
}

/// The core on this thread is the test channel's (`true`) or the released one's.
pub fn set_test_channel(on: bool) {
    TEST_CHANNEL.with(|c| c.set(on));
}

/// The product's name, as people are shown it on this channel.
pub fn name() -> &'static str {
    if TEST_CHANNEL.with(Cell::get) { TEST } else { STABLE }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Core;
    use crate::testing::{FakeHost, run};

    #[test]
    fn the_name_is_the_channels() {
        assert_eq!(name(), "still.fail");
        set_test_channel(true);
        assert_eq!(name(), "youdid.wtf");
        set_test_channel(false);
        assert_eq!(name(), "still.fail");
    }

    #[test]
    fn a_core_takes_its_channel_from_its_host() {
        run(async {
            for (beta, web_on_test, expected) in [(false, false, STABLE), (true, false, TEST), (false, true, TEST)] {
                let host = FakeHost::new();
                host.beta.set(beta);
                host.test_channel.set(web_on_test);
                let _core = Core::new(host.clone()).await;
                assert_eq!(name(), expected, "beta {beta}, web on the test channel {web_on_test}");
            }
        });
    }

    #[test]
    fn what_the_core_says_names_the_channels_product() {
        for (on, name) in [(false, "still.fail"), (true, "youdid.wtf")] {
            set_test_channel(on);
            assert_eq!(crate::cloud::cloud_error("invalid_email", 400).message, format!("要填对方登录 {name} 用的邮箱"));
            let pill = crate::pill::raw(&serde_json::Value::Null, Some(&serde_json::json!({ "state": "trouble" }))).map(|(p, _)| p["text"].clone());
            assert_eq!(pill, Some(serde_json::json!(format!("连不上 {name} cloud"))));
        }
        set_test_channel(false);
    }
}
