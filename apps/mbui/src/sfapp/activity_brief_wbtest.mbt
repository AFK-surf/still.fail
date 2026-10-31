// A brief activity between two longer ones should not start a change the reader has to watch twice.

///|
let brief_activity : String = "正在检查一个很快完成的步骤"

///|
let lasting_activity : String = "正在处理最终结果"

///|
let brief_step_ms : Double = 160.0

///|
let before_step_ends_ms : Double = 140.0

///|
let later_step_shown_ms : Double = 1200.0

///|
test "activity: a fleeting step does not interrupt the words already being read" {
  let src = fixture_app("chat-working")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=740.0, platform=2)
  t.run_for(squeeze_opening)
  @sffixture.fix_later(1.0, fn() { @sffixture.fix_working_now.val = ("call:2", brief_activity) })
  @sffixture.fix_later(1.0 + brief_step_ms, fn() { @sffixture.fix_working_now.val = ("call:3", lasting_activity) })
  t.run_for(before_step_ends_ms)
  assert_true(t.words().iter().all(fn(w) { w.0 != brief_activity }), msg="a brief step has begun replacing the current words")
  t.run_for(later_step_shown_ms)
  assert_true(t.find(lasting_activity) is Some(_), msg="the lasting next step is shown")
  assert_true(t.words().iter().all(fn(w) { w.0 != brief_activity }), msg="the fleeting step did not return")
}

///|
test "activity: returning to the same words after a brief step does not animate a change" {
  let src = fixture_app("chat-working")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=740.0, platform=2)
  t.run_for(squeeze_opening)
  @sffixture.fix_later(1.0, fn() { @sffixture.fix_working_now.val = ("call:2", brief_activity) })
  @sffixture.fix_later(1.0 + brief_step_ms, fn() { @sffixture.fix_working_now.val = ("call:1", @sffixture.working_step) })
  t.run_for(before_step_ends_ms)
  assert_true(t.words().iter().all(fn(w) { w.0 != brief_activity }), msg="a brief step has begun replacing the current words")
  t.run_for(later_step_shown_ms)
  assert_true(t.find(@sffixture.working_step) is Some(_), msg="the original step remains")
  assert_true(t.words().iter().all(fn(w) { w.0 != brief_activity }), msg="the fleeting step did not return")
}

///|
test "activity: a pending step keeps its place when its own words change" {
  let src = fixture_app("chat-working")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=740.0, platform=2)
  t.run_for(squeeze_opening)
  @sffixture.fix_later(1.0, fn() { @sffixture.fix_working_now.val = ("call:2", brief_activity) })
  @sffixture.fix_later(201.0, fn() { @sffixture.fix_working_now.val = ("call:2", lasting_activity) })
  t.run_for(@sfbase.glyph_change_in_ms + @sfbase.glyph_change_in_ms / 2.0)
  assert_true(t.find(lasting_activity) is Some(_), msg="the same step's latest words are shown")
  assert_true(t.words().iter().all(fn(w) { w.0 != brief_activity }), msg="its earlier words did not enter")
}

///|
test "activity: reduced motion also skips a fleeting step" {
  let src = fixture_app("chat-working")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=740.0, platform=2)
  t.run_for(squeeze_opening)
  t.set_reduce_motion(true)
  @sffixture.fix_later(1.0, fn() { @sffixture.fix_working_now.val = ("call:2", brief_activity) })
  @sffixture.fix_later(1.0 + brief_step_ms, fn() { @sffixture.fix_working_now.val = ("call:3", lasting_activity) })
  t.run_for(before_step_ends_ms)
  assert_true(t.words().iter().all(fn(w) { w.0 != brief_activity }), msg="a brief step is not shown")
  t.run_for(later_step_shown_ms)
  assert_true(t.find(lasting_activity) is Some(_), msg="the lasting step is shown")
  t.set_reduce_motion(false)
}

///|
test "activity: an important brief step is shown and given time to be read" {
  let src = fixture_app("chat-working")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=740.0, platform=2)
  t.run_for(squeeze_opening)
  @sffixture.fix_later(1.0, fn() {
    @sffixture.fix_working_now.val = ("call:2", brief_activity)
    @sffixture.fix_working_important.val = true
  })
  @sffixture.fix_later(1.0 + brief_step_ms, fn() {
    @sffixture.fix_working_now.val = ("call:3", lasting_activity)
    @sffixture.fix_working_important.val = false
  })
  t.run_for(before_step_ends_ms)
  assert_true(t.find(brief_activity) is Some(_), msg="the important step starts appearing promptly")
  t.run_for(@sfbase.glyph_change_in_ms)
  assert_true(t.find(brief_activity) is Some(_), msg="the important step remains readable after it has finished")
  t.run_for(later_step_shown_ms)
  assert_true(t.find(lasting_activity) is Some(_), msg="the latest step eventually replaces it")
}

///|
test "activity: an important step that comes during a change is not lost" {
  let src = fixture_app("chat-working")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=740.0, platform=2)
  t.run_for(squeeze_opening)
  @sffixture.fix_later(1.0, fn() { @sffixture.fix_working_now.val = ("call:2", lasting_activity) })
  t.run_for(@sfbase.glyph_change_in_ms + @sfbase.glyph_change_in_ms / 4.0)
  @sffixture.fix_later(1.0, fn() {
    @sffixture.fix_working_now.val = ("call:3", brief_activity)
    @sffixture.fix_working_important.val = true
  })
  @sffixture.fix_later(1.0 + brief_step_ms, fn() {
    @sffixture.fix_working_now.val = ("call:4", @sffixture.working_step)
    @sffixture.fix_working_important.val = false
  })
  t.run_for(brief_step_ms + @sfbase.glyph_change_in_ms)
  assert_true(t.find(brief_activity) is Some(_), msg="the important step is shown after the change already under way")
  t.run_for(later_step_shown_ms)
  assert_true(t.find(@sffixture.working_step) is Some(_), msg="the line catches up with the latest step")
}
