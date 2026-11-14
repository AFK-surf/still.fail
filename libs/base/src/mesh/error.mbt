///|
/// What the mesh fails with: `code` for a program to go by ("mesh" where the peer was not reached or what it said was
/// not understood; "credential_refused" where it refused the credential; "invalid_params"; a code the peer's refusal
/// names), `message` for people, in their language (words.mbt), and `cause`: what was said underneath (the shell's
/// words), for a log, never shown.
pub(all) suberror MeshError {
  MeshError(code~ : String, message~ : String, cause~ : String)
}

///|
/// The code of what failed: a `MeshError`'s; "" of anything else.
pub fn code_of(e : Error) -> String {
  match e {
    MeshError(code~, ..) => code
    _ => ""
  }
}

///|
/// What failed, said in a line: a `MeshError` as its code and its words, anything else as it says itself.
pub fn said(e : Error) -> String {
  match e {
    MeshError(code~, message~, ..) => "\{code}: \{message}"
    @shell.ShellError(m) => m
    e => e.to_string()
  }
}

///|
fn text_of(e : Error) -> String {
  match e {
    @shell.ShellError(m) => m
    MeshError(message~, ..) => message
    e => e.to_string()
  }
}

///|
/// Failed in the mesh's own words.
fn failed(key : String, args? : Map[String, String]) -> MeshError {
  MeshError(code="mesh", message=say(key, args?), cause="")
}

///|
/// Failed under the mesh (the shell's error, a parser's), said as `key`, what was said kept as the cause.
fn under(key : String, e : Error) -> MeshError {
  MeshError(code="mesh", message=say(key), cause=text_of(e))
}

///|
/// The connection failed once it was up.
fn cut(e : Error) -> MeshError {
  under("cut", e)
}

///|
/// The peer was not reached.
fn unreached(e : Error) -> MeshError {
  under("unreached", e)
}
