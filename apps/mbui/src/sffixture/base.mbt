// The made-up core (fixtures): what each topic says and how each call is answered over made-up data, for the app's
// tests and its tools (sffix, sffilm, sflayout, sfreplay); never imported by the app itself (detlint's fixture-import).
// What it reads of sfbase (the views, the pages, the model's helpers), by name.

using @sfbase {
  update_version, set_update_source, workspace_of,
  type Attachment,
  type DriveAt,
  type Source,
  type Topic,
  base_name,
  dv_absolute,
  dv_join,
  dv_name,
  dv_parent,
  dv_words,
  field,
  fill,
  flag,
  items,
  number,
  open_preview,
  pv_strip,
  seq_of,
  text,
  tr,
  update,
  viewer,
}
