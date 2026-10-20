// 67-lock-wait (e2e/traces/lock-wait.trace): safe mode turned on by alice's other device with this app's device left
// out: in Home's place the app shows that it waits to be approved; 发送批准请求 reaches the other device (lock.pair),
// which shows a code; a wrong code typed says how many tries are left (lock.pairCode). Safe mode off again: Home.

///|
test "67-lock-wait" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_lock_wait, seed~)
    f.see("等待批准此设备")
    f.see("发送批准请求")
    f.tap("发送批准请求")
    f.see("输入你的受信任设备上显示的安全码")
    // a wrong code (lock.pairCode: pair_wrong, two tries left; f.end has it asked with these words), then safe mode
    // turned off by the other device: what the run's other device said later comes as soon as it may, so the moment
    // 安全码不对 showed is gone by the frame after the code
    f.type_text("000000")
    f.see("端到端测试")
    f.end()
  })
}
