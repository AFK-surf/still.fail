// What the pages read of sfbase, by their own names.
using @sfbase {
  type Agent,
  type Attachment,
  type Card,
  type ChatRef,
  type ChatView,
  type Choice,
  type Elsewhere,
  type Emits,
  type Entry,
  type Install,
  type Message,
  type Outgoing,
  type Quote,
  type SendFlight,
  type Source,
  type Stamp,
  type Turns,
  type VaultAsk,
  absolute_times,
  act,
  act_rooms,
  agent_json,
  app,
  app_in_front,
  asks_in_view,
  chat_params,
  close_turn_ms,
  core_doing,
  core_failed,
  count,
  detail_asked,
  doing,
  download_cancel,
  download_of,
  download_retry,
  each_second,
  elapsed,
  emit_away,
  emit_emitting,
  emit_flight,
  emit_folded,
  emit_goes,
  emit_out,
  emits,
  error_words,
  field,
  first_line,
  flag,
  flash_of,
  flight_bubble,
  flight_ground_of,
  flight_landing,
  flight_p,
  flight_placed,
  flight_settled_of,
  flight_takes,
  flight_up,
  floor_of,
  go_to_words,
  go_tos,
  items,
  linger_out_ms,
  list_after,
  list_frame,
  local_sent,
  message_runs,
  note_thumb,
  number,
  open_link,
  open_preview,
  opt_number,
  reading_of,
  readings,
  screen_links,
  second_ms,
  sent_picture,
  seq_key,
  seq_s,
  text,
  this_machine,
  thumb_shows,
  toast_later,
  video_still,
  viz_file_of,
  viz_mermaid_block,
  viz_open_full,
  working_turn_ms,
  workspace_of,
  writing,
  writing_text,
}

///|
pub fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}


///|
pub fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
using @settings {type Core, type Asked}
