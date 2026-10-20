/** Product380: this is an unimplemented deletion policy, not evidence of erasure or revocation. */
export const deletionCoverage = {
  coverageIncomplete: true,
  canDelete: false,
  categories: [
    { id: "identity", action: "delete", status: "planned", detail: "拟删除云端登录身份、个人资料及保存的 Apple 授权；尚未实现或验证" },
    { id: "sessions", action: "revoke_then_delete", status: "planned", detail: "拟撤销账号的登录和访问权限，再清理成员关系；未连接服务的电脑仍可能接受旧凭据，撤销通知尚待实现或验证" },
    { id: "cloud_personal", action: "delete", status: "planned", detail: "拟删除本人私有反馈、成员关系及可按登录身份确认的待加入资格；不会按非唯一邮箱批量删除，覆盖仍待验证" },
    { id: "cloud_private_objects", action: "delete", status: "unverified", detail: "个人云设置和私有上传内容的完整存储范围与删除覆盖尚未核实" },
    { id: "cloud_shared_attribution", action: "delete", status: "unimplemented", detail: "拟删除你在共享空间发送的消息、上传内容及其中的个人信息，不会仅移除署名而保留你的内容；尚未实现" },
    { id: "logs_telemetry", action: "delete_or_deidentify", status: "unverified", detail: "日志与遥测中的个人信息处理范围及实际剩余保留期限尚未核实" },
    { id: "backups", action: "delete_or_expire", status: "unverified", detail: "备份中的个人信息、消息和上传内容的删除覆盖及实际保留期限尚未核实" },
    { id: "local_preferences", action: "clear_or_isolate", status: "unverified", detail: "拟清理本机个人偏好、草稿及临时附件，同时保护其他账号的数据；具体范围尚未核实" },
    { id: "node_copies", action: "delete_then_acknowledge", status: "unimplemented", detail: "服务管理的电脑会话、上传内容及其中的个人信息也在拟删除范围内，清理结果仍需电脑确认；尚未实现。这不会清空电脑，也不会删除与这个账号无关的文件。仅由用户独立保存、导出且不受服务管理的副本不在服务删除范围内" },
  ],
  sharedPreservation: "拟保留其他成员的内容和共享工作区，不会自动转移所有权或删除工作区；你的共享消息、上传内容及其中的个人信息仍在拟删除范围内。此方案尚未实现或验证。",
  offlineAccess: {
    status: "proposed_unverified",
    maximumGrantSeconds: 30 * 24 * 60 * 60,
    grantLifetimeStart: "original_grant_issuance",
    existingRevocationReplaySeconds: 31 * 24 * 60 * 60,
    instantRevocationGuaranteed: false,
    detail: "拟定访问规则，尚待验证：未连接服务的电脑可能仍接受旧凭据访问，最长30天。它重新连接后会收到撤销通知。这个访问期限不代表电脑上的相关内容会在30天内自动清除。访问期限从原始授权签发时起算。",
  },
  securityRetention: {
    status: "proposed_unverified",
    receiptRetentionSeconds: null,
    proposedReceiptRetentionSeconds: 32 * 24 * 60 * 60,
    purpose: "拟仅保留拒绝旧凭据和确认重复删除所需的最小安全记录；31天撤销重放加24小时余量形成32天方案，尚未实现或验证。这不是实际保留期限、全部日志的保留规则或 Apple 审核结论；字段、清理和到期方案仍待核实。",
  },
} as const;
