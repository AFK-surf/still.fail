// The words, as the Android app says them in Chinese (ember client/i18n/catalog/zh: android-chat.json,
// android-settings.json, android-misc.json, common.json); `{name}` is put in by `fill`.

///|
let zh : Map[String, String] = {
  "android-chat.archive": "归档",
  "android-chat.archived": "已归档",
  "android-chat.info.title": "对话信息",
  "android-settings.station.first": "添加第一台 station",
  "android-settings.station.firstNote": "agent 在你的机器上运行。首先添加一台 Mac 或 Linux 机器。",
  "android-chat.home.empty.many": "暂无会话。在 Slack 中 @ 它们，或",
  "android-chat.home.empty.mine": "暂无你参与的会话",
  "android-chat.home.empty.one": "暂无会话。在 Slack 中 @ 它，或",
  "android-chat.home.empty.watching": "暂无监控中的会话",
  "android-chat.home.filter.all": "全部",
  "android-chat.home.filter.archived": "已归档",
  "android-chat.home.filter.label": "筛选会话：{filter}",
  "android-chat.home.filter.mine": "我参与的",
  "android-chat.home.filter.watching": "监控中",
  "android-chat.home.invited": "有邀请",
  "android-chat.home.loading": "正在读取会话",
  "android-chat.home.mark.alert": "需要处理",
  "android-chat.home.mark.busy": "工作中",
  "android-chat.home.mark.done": "已完成，有新消息",
  "android-chat.home.mark.other": "等待他人",
  "android-chat.home.mark.wait": "等待你处理",
  "android-chat.home.settings": "设置",
  "android-chat.newChat": "新建对话",
  "android-chat.search.field": "搜索全部内容",
  "android-misc.bar.place.chats": "对话",
  "android-misc.workspace.addAccount": "登录其他账号",
  "android-misc.workspace.addAccount.sub": "保留已登录账号，添加另一个账号",
  "android-misc.workspace.current": "当前使用",
  "android-misc.workspace.new": "新建 workspace",
  "android-misc.workspace.none": "尚未加入任何 workspace",
  "android-misc.workspace.none.lead": "可以请正在使用 {app} 的人将 {email} 邀请进他们的 workspace，也可以自行创建",
  "android-misc.workspace.others": "其他 workspace",
  "android-misc.workspace.sheet.title": "切换 workspace",
  "android-misc.workspaces.loadFailed": "无法读取你的 workspace",
  "android-misc.workspaces.loading": "正在读取你的 workspace",
  "android-settings.signIn.google": "登录或注册",
  "android-settings.signIn.many": "可同时登录多个账号，随时切换 workspace。",
  "android-settings.signIn.note": "登录后，你所在 workspace 的所有 station 和会话都会显示在这里。",
  "android-settings.signIn.title": "让 agent 持续工作",
  "common.opening": "正在打开",
  "common.reading": "正在读取",
}

///|
/// The words for `key`.
pub fn tr(key : String) -> String {
  zh.get(key).unwrap_or(key)
}

///|
/// The words for `key` with `{name}`s put in.
pub fn fill(key : String, args : Array[(String, String)]) -> String {
  let mut s = tr(key)
  for a in args {
    s = s.replace_all(old="{" + a.0 + "}", new=a.1)
  }
  s
}
