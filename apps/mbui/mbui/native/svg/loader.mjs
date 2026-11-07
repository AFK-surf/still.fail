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
    createPng(width, height) {
      let handle = x.mbpng_new(width, height);
      if (!handle) throw new RangeError('Invalid PNG dimensions');
      let result;
      return {
        add(bytes, count) {
          if (!handle) throw new Error('PNG encoder is closed');
          if (!Number.isInteger(count) || count < 0 || count > 0x7fffffff) throw new RangeError('Invalid PNG row count');
          const p = upload(bytes);
          try {
            if (!x.mbpng_add(handle, p, bytes.length, count)) throw new RangeError('Invalid PNG row input');
          } finally { x.mbsvg_buffer_free(p, bytes.length); }
        },
        end() {
          if (result) return result;
          if (!handle) throw new Error('PNG encoder is closed');
          const out = x.mbpng_end(handle);
          handle = 0;
          if (!out) throw new Error('PNG encoding failed');
          try { result = new Uint8Array(x.memory.buffer, x.mbpng_output_ptr(out), x.mbpng_output_len(out)).slice(); }
          finally { x.mbpng_output_free(out); }
          return result;
        },
        close() {
          if (handle) x.mbpng_free(handle);
          handle = 0;
        },
      };
    },
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
