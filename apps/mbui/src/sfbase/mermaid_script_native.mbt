///|
/// mermaid as the core is given it (`mermaid.load`, viz_mermaid.mbt): its Hermes bytecode (mermaid_hbc.mbt), unzipped
/// (once a run: the core keeps it).
fn viz_mermaid_script() -> Bytes? {
  @zip.gunzip(mermaid_hbc_gz)
}
