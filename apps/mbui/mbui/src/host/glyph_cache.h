// Cluster identity and storage shared by Pango and DirectWrite. Raster metrics remain platform-owned.
#ifdef _WIN32
typedef WCHAR glyph_char;
#else
typedef uint16_t glyph_char;
#endif

static uint32_t hash(const glyph_char *s, int len, double size, int weight, int style) {
  uint32_t h = 2166136261u;
  for (int i = 0; i < len; i++) h = (h ^ s[i]) * 16777619u;
  h = (h ^ (uint32_t)(size * 64)) * 16777619u;
  h = (h ^ (uint32_t)style) * 16777619u;
  return (h ^ (uint32_t)weight) * 16777619u;
}

static int same(const glyph_entry *e, const glyph_char *s, int len, double size, int weight, int style) {
  return e->len == len && e->size == size && e->weight == weight && e->style == style &&
         memcmp(pool + e->off, s, (size_t)len * sizeof(glyph_char)) == 0;
}

static void table_put(int id) {
  glyph_entry *e = &entries[id];
  size_t i = hash(pool + e->off, e->len, e->size, e->weight, e->style) & (table_cap - 1);
  while (table[i]) i = (i + 1) & (table_cap - 1);
  table[i] = id + 1;
}

static int intern(const glyph_char *s, int len, double size, int weight, int style) {
  if (table_cap) {
    size_t i = hash(s, len, size, weight, style) & (table_cap - 1);
    for (; table[i]; i = (i + 1) & (table_cap - 1))
      if (same(&entries[table[i] - 1], s, len, size, weight, style)) return table[i] - 1;
  }
  if (n_entries == cap_entries) {
    cap_entries = cap_entries ? cap_entries * 2 : 1024;
    entries = (glyph_entry *)realloc(entries, sizeof(glyph_entry) * (size_t)cap_entries);
  }
  if (pool_len + (size_t)len > pool_cap) {
    pool_cap = (pool_len + len) * 2 + 4096;
    pool = (glyph_char *)realloc(pool, pool_cap * sizeof(glyph_char));
  }
  memcpy(pool + pool_len, s, (size_t)len * sizeof(glyph_char));
  int id = n_entries++;
#ifdef _WIN32
  entries[id] = {(int)pool_len, len, size, weight, style, 0, 0, 0, 0, 0, 0, 0, false};
#else
  entries[id] = (glyph_entry){(int)pool_len, len, size, weight, style, 0, 0, 0, 0, 0};
#endif
  pool_len += len;
  if ((size_t)n_entries * 2 > table_cap) {
    free(table);
    table_cap = table_cap ? table_cap * 2 : 4096;
    table = (int *)calloc(table_cap, sizeof(int));
    for (int j = 0; j < n_entries; j++) table_put(j);
  } else {
    table_put(id);
  }
  return id;
}

