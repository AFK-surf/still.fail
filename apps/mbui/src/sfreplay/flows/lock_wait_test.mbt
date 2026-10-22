// 67-lock-wait (e2e/traces/lock-wait.trace): safe mode turned on by alice's other device with this app's device left
// out: in Home's place the app shows that it waits to be approved; 发送批准请求 reaches the other device (lock.pair),
// which shows a code; a wrong code typed says how many tries are left (lock.pairCode). Safe mode off again: Home.

///|
test "67-lock-wait" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("lock-wait"), seed~)
    // (the station locked before the app starts, then let wait and unlocked: a live run's steps)
    f.before("peer lock-on")
    f.see("等待批准此设备")
    f.see("发送批准请求")
    // (the other device waiting for this one's request as the app asks it: beside the script)
    f.peer_aside("peer lock-await 60")
    f.tap("发送批准请求")
    f.see("输入你的受信任设备上显示的安全码")
    // a wrong code (lock.pairCode: pair_wrong, two tries left; f.end has it asked with these words)
    f.type_text("000000")
    f.see("安全码不对")
    // then safe mode turned off by the other device: Home
    f.peer("peer lock-off")
    f.see("端到端测试")
    f.end()
  })
}
