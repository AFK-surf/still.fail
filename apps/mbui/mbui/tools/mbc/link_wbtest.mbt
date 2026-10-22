///|
test "MSVC receives every split object and linker option through one short command" {
  let args = [b"C:\\Program Files\\MSVC\\cl.exe", b"/nologo", b"/FeC:\\build tree\\app.exe"]
  for i in 0..<400 {
    args.push(utf8("C:\\build tree\\app\\_build\\native\\release\\build\\stillfail\\stillfail\\stillfail.mbc\\u_stillfail_sf_\{i}.obj"))
  }
  args.push(b"/link")
  args.push(b"/LIBPATH:C:\\Program Files\\SDK\\lib")
  args.push(b"/SUBSYSTEM:WINDOWS")
  assert_true(list2cmdline(args).length() > 32767)
  let rsp = tmp_path("link with spaces.rsp")
  let command = msvc_link_command(args, rsp)
  let contents = read_file(rsp).unwrap()
  let decoded = response_files(command[1:].to_array(), true)
  let _ = c_remove(rsp)
  assert_eq(command.length(), 2)
  assert_true(list2cmdline(command).length() < 32767)
  assert_eq(decoded, args[1:].to_array())
  assert_eq(count(contents, b"\n"), 1)
  assert_true(ends(contents, b"/SUBSYSTEM:WINDOWS\n"))
}
