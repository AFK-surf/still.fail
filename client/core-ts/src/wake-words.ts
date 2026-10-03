// What wake.rs gives up with, matched as it is (error.rs, core.rs).

/// What a request given up fails with.
export const DROPPED = "页面回到前台，重新请求";
/// What a stream taken for gone ends with.
export const GONE = "页面回到前台，重新连接";
/// What everything under way fails with when the network changed.
export const NETWORK = "网络变了，重新连接";
