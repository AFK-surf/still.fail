// The made-up core put back as the app is (its reset), and told each frame's Ctx (its timers then the runtime's): wires
// given sfbase as this package is linked (a test's program, a tool's), the app calling them without knowing it is
// there.

///|
fn init {
  @sfbase.made_reset.val = fixture_reset
  @sfbase.made_frame.val = fn(c) { fix_ctx.val = Some(c) }
}

///|
/// The made-up core as at the start: its chats, its drive, what it keeps of the browsing, its clock.
pub fn fixture_reset() -> Unit {
  new_fix.station = "st1"
  new_fix.model = "claude-opus-5-5"
  new_fix.runtime = "claude"
  new_fix.effort = "high"
  new_fix.d_model = "claude-opus-5-5"
  new_fix.d_runtime = "claude"
  new_fix.d_effort = "high"
  new_fix.context = ""
  new_fix.d_profile = ""
  new_fix.d_profiles.clear()
  new_fix.d_none = false
  new_fix.made = 0
  new_fix.reading = 0
  new_fix.crowded = false
  new_fix.tall = false
  new_fix.preset = ""
  new_fix.presets_late = false
  new_fix.clones.clear()
  new_fix.cloned.clear()
  new_fix.liked.clear()
  fix_forgotten.clear()
  new_fix.providers = false
  new_fix.borrow = false
  fix_presets_said.val = 0
  fix_job_more.val = 0
  new_fix.presets.clear()
  new_fix.presets.push_iter([fix_preset_design(), fix_preset("p-tc", "web-app + backend", ["web-app", "backend"], "")].iter())
  fix_chats.clear()
  fix_timers.clear()
  fix_downloads.clear()
  fix_keeping_reset()
  fix_done.val = 0
  fix_unsaid.clear()
  fix_drafts.clear()
  fix_composers.clear()
  fix_put_up.clear()
  fix_writes.clear()
  fix_xshared.clear()
  fix_decided.clear()
  fix_replied.clear()
  fix_card_replies.clear()
  fix_reply_at.clear()
  fix_pace.val = (fix_deliver_ms, fix_answer_ms, fix_turn_end_ms)
  fix_sent_for.val = -1.0
  fix_core_for.val = 0.0
  fix_vault.val = ""
  fix_phone.val = ""
  fix_phone_scope.val = ""
  fix_phone_link.val = ""
  fix_rig.val = ""
  fix_rig_asked.clear()
  fix_working_now.val = ("call:1", working_step)
  fix_working_important.val = false
  fix_working_status.val = "running"
  kept_chats.clear()
  fixture_pictures.clear()
  fix_threads.clear()
  fix_browse_reset()
  fix_ctx.val = None
  fix_clock.val = None
  fix_serial.val = 0
  fix_stream_ids.val = 0
  fix_fetches.clear()
  fix_folders.clear()
  fix_places.clear()
  fix_transfers.clear()
  fix_reads.clear()
}
