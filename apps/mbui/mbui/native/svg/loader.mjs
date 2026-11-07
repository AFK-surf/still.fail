// Install the returned interface before starting MoonBit's JS entry point.
export async function loadSvg(module) {
  const loaded = await WebAssembly.instantiate(module, {});
  const x = (loaded.instance ?? loaded).exports;
  function upload(bytes) {
    const p = x.mbsvg_buffer_new(bytes.length);
    new Uint8Array(x.memory.buffer, p, bytes.length).set(bytes);
    return p;
  }
  return {
    create: () => x.mbsvg_fonts_new(),
    free: db => x.mbsvg_fonts_free(db),
    add(db, bytes) {
      const p = upload(bytes);
      try { x.mbsvg_fonts_add(db, p, bytes.length); }
      finally { x.mbsvg_buffer_free(p, bytes.length); }
    },
    draw(db, bytes, side) {
      const p = upload(bytes);
      let out;
      try { out = x.mbsvg_rasterize_app(db, p, bytes.length, side); }
      finally { x.mbsvg_buffer_free(p, bytes.length); }
      if (!out) return new Uint8Array();
      const n = x.mbsvg_raster_length(out);
      try { return new Uint8Array(x.memory.buffer, out, n).slice(); }
      finally { x.mbsvg_buffer_free(out, n); }
    },
  };
}
