// The app's widgets for the system's accessibility (Orca, and whatever reads the screen through AT-SPI), as the Mac's
// mac_app.m gives them to VoiceOver: an accessible object of each node the app told (src/ui/a11y.mbt's updates,
// @hostapi.a11y_tree: what changed, kept by its number; those of no use of their own, flags v, none: what they hold
// their holder's), each a GtkAccessible of its own (GTK 4.10's interface for one that is no widget) under the canvas:
// its parent, its first child and its next sibling as the nodes say, its bounds from its holder's, its role by the
// node's (GtkAccessibleRole), its name, description, value, range and state set as they are told. The keyboard's focus
// is the node the app says has it (a platform state, read as it is asked). What a reader asks of a node is not taken here:
// GTK 4.14 gives an accessible that is no widget no actions of AT-SPI's; the app's keys reach what has the focus.
// The app tells its widgets while a screen reader runs (AT-SPI's bus says so: org.a11y.Status, its ScreenReaderEnabled,
// a frame asked for as it changes). MBUI_A11Y_SELFCHECK=1 (host_contract.sh linux a11y): told as though one read them,
// the canvas's accessibles walked as AT-SPI walks them, each said ("A11Y node <role> <label>"), and the button named
// "A11YCHECK press" asked to be pressed as the other hosts' readers ask it.
// Included by linux_app.c (area, schedule).

typedef struct {
  int nid, parent, widget;
  char *role, *flags, *label, *value, *help, *actions;
  double x, y, w, h;
  int range;
  double low, at, high;
  GArray *kids;  // int: the numbers of what it holds, in their order
  GObject *obj;  // its accessible, made as it is first asked for
} A11yNode;

typedef struct {
  GObject parent;
  int nid;
  GtkAccessibleRole role;
  GtkATContext *ctx;
} MBA11yObj;
typedef struct {
  GObjectClass parent;
} MBA11yObjClass;

static GHashTable *a11y_nodes;  // int → A11yNode
static int a11y_focus;
static gboolean a11y_selfcheck_done;

static A11yNode *a11y_node(int nid) { return a11y_nodes ? g_hash_table_lookup(a11y_nodes, GINT_TO_POINTER(nid)) : NULL; }
static gboolean a11y_has(const char *letters, char c) { return letters && strchr(letters, c) != NULL; }

static void a11y_node_free(gpointer p) {
  A11yNode *n = p;
  g_free(n->role), g_free(n->flags), g_free(n->label), g_free(n->value), g_free(n->help), g_free(n->actions);
  g_array_free(n->kids, TRUE);
  if (n->obj) g_object_unref(n->obj);
  g_free(n);
}

// what node `nid` holds as accessibles: those of no use of their own (flags v) left out, what they hold in their place
static void a11y_shown_kids(int nid, GArray *out) {
  A11yNode *n = a11y_node(nid);
  if (!n) return;
  for (guint i = 0; i < n->kids->len; i++) {
    int k = g_array_index(n->kids, int, i);
    A11yNode *c = a11y_node(k);
    if (!c) continue;
    if (a11y_has(c->flags, 'v')) a11y_shown_kids(k, out);
    else g_array_append_val(out, k);
  }
}

// the nearest that holds node `n` of use of its own (0: the canvas)
static int a11y_shown_holder(A11yNode *n) {
  A11yNode *p = a11y_node(n->parent);
  while (p && p->nid && a11y_has(p->flags, 'v')) p = a11y_node(p->parent);
  return p ? p->nid : 0;
}

// where node `n` is in the canvas: its holders' places and its own, each from where its holder is (a11y.mbt's head)
static void a11y_place(A11yNode *n, double *x, double *y) {
  *x = n->x, *y = n->y;
  for (A11yNode *p = a11y_node(n->parent); p && p->nid; p = a11y_node(p->parent)) *x += p->x, *y += p->y;
}

static GtkAccessibleRole a11y_role(const char *r) {
  static const struct {
    const char *name;
    GtkAccessibleRole role;
  } roles[] = {
      {"Text", GTK_ACCESSIBLE_ROLE_LABEL},
      {"Group", GTK_ACCESSIBLE_ROLE_GROUP},
      {"Button", GTK_ACCESSIBLE_ROLE_BUTTON},
      {"Link", GTK_ACCESSIBLE_ROLE_LINK},
      {"Checkbox", GTK_ACCESSIBLE_ROLE_CHECKBOX},
      {"Switch", GTK_ACCESSIBLE_ROLE_SWITCH},
      {"Radio", GTK_ACCESSIBLE_ROLE_RADIO},
      {"RadioGroup", GTK_ACCESSIBLE_ROLE_RADIO_GROUP},
      {"Slider", GTK_ACCESSIBLE_ROLE_SLIDER},
      {"ProgressBar", GTK_ACCESSIBLE_ROLE_PROGRESS_BAR},
      {"Tab", GTK_ACCESSIBLE_ROLE_TAB},
      {"TabList", GTK_ACCESSIBLE_ROLE_TAB_LIST},
      {"TabPanel", GTK_ACCESSIBLE_ROLE_TAB_PANEL},
      {"Dialog", GTK_ACCESSIBLE_ROLE_DIALOG},
      {"AlertDialog", GTK_ACCESSIBLE_ROLE_ALERT_DIALOG},
      {"Tooltip", GTK_ACCESSIBLE_ROLE_TOOLTIP},
      {"Menu", GTK_ACCESSIBLE_ROLE_MENU},
      {"MenuBar", GTK_ACCESSIBLE_ROLE_MENU_BAR},
      {"MenuItem", GTK_ACCESSIBLE_ROLE_MENU_ITEM},
      {"MenuItemCheckbox", GTK_ACCESSIBLE_ROLE_MENU_ITEM_CHECKBOX},
      {"MenuItemRadio", GTK_ACCESSIBLE_ROLE_MENU_ITEM_RADIO},
      {"Listbox", GTK_ACCESSIBLE_ROLE_LIST_BOX},
      {"Option", GTK_ACCESSIBLE_ROLE_OPTION},
      {"Combobox", GTK_ACCESSIBLE_ROLE_COMBO_BOX},
      {"Toolbar", GTK_ACCESSIBLE_ROLE_TOOLBAR},
      {"Separator", GTK_ACCESSIBLE_ROLE_SEPARATOR},
      {"Image", GTK_ACCESSIBLE_ROLE_IMG},
      {"TextField", GTK_ACCESSIBLE_ROLE_TEXT_BOX},
      {"Status", GTK_ACCESSIBLE_ROLE_STATUS},
      {"Region", GTK_ACCESSIBLE_ROLE_REGION},
      {"Navigation", GTK_ACCESSIBLE_ROLE_NAVIGATION},
      {"Form", GTK_ACCESSIBLE_ROLE_FORM},
      {"Heading", GTK_ACCESSIBLE_ROLE_HEADING},
  };
  for (gsize i = 0; i < G_N_ELEMENTS(roles); i++)
    if (strcmp(roles[i].name, r) == 0) return roles[i].role;
  return GTK_ACCESSIBLE_ROLE_GENERIC;
}

static GObject *a11y_obj(int nid);

// the accessible of node `nid` (the canvas for 0), a reference of its own (as GtkAccessible's getters give one)
static GtkAccessible *a11y_ref(int nid) {
  if (nid == 0) return area ? GTK_ACCESSIBLE(g_object_ref(area)) : NULL;
  GObject *o = a11y_obj(nid);
  return o ? GTK_ACCESSIBLE(g_object_ref(o)) : NULL;
}

// the first of what node `nid` holds as accessibles, or the one after `after` among them (a reference of its own)
static GtkAccessible *a11y_kid_after(int nid, int after) {
  GArray *kids = g_array_new(FALSE, FALSE, sizeof(int));
  a11y_shown_kids(nid, kids);
  GtkAccessible *out = NULL;
  gboolean past = after == 0;
  for (guint i = 0; i < kids->len && !out; i++) {
    int k = g_array_index(kids, int, i);
    if (past) out = a11y_ref(k);
    else if (k == after) past = TRUE;
  }
  g_array_free(kids, TRUE);
  return out;
}

static GtkATContext *a11y_obj_context(GtkAccessible *self) {
  MBA11yObj *o = (MBA11yObj *)self;
  if (!o->ctx && area) o->ctx = gtk_at_context_create(o->role, self, gtk_widget_get_display(area));
  return o->ctx ? g_object_ref(o->ctx) : NULL;
}

static gboolean a11y_obj_state(GtkAccessible *self, GtkAccessiblePlatformState state) {
  A11yNode *n = a11y_node(((MBA11yObj *)self)->nid);
  if (!n) return FALSE;
  switch (state) {
    case GTK_ACCESSIBLE_PLATFORM_STATE_FOCUSABLE: return a11y_has(n->actions, 'a') || a11y_has(n->actions, 'f');
    case GTK_ACCESSIBLE_PLATFORM_STATE_FOCUSED: return n->nid == a11y_focus;
    default: return FALSE;
  }
}

static GtkAccessible *a11y_obj_parent(GtkAccessible *self) {
  A11yNode *n = a11y_node(((MBA11yObj *)self)->nid);
  return n ? a11y_ref(a11y_shown_holder(n)) : NULL;
}

static GtkAccessible *a11y_obj_first(GtkAccessible *self) { return a11y_kid_after(((MBA11yObj *)self)->nid, 0); }

static GtkAccessible *a11y_obj_next(GtkAccessible *self) {
  A11yNode *n = a11y_node(((MBA11yObj *)self)->nid);
  return n ? a11y_kid_after(a11y_shown_holder(n), n->nid) : NULL;
}

// its bounds from its parent accessible's (the canvas's: from the canvas's top left), in whole points
static gboolean a11y_obj_bounds(GtkAccessible *self, int *x, int *y, int *w, int *h) {
  A11yNode *n = a11y_node(((MBA11yObj *)self)->nid);
  if (!n) return FALSE;
  double ax, ay, hx = 0, hy = 0;
  a11y_place(n, &ax, &ay);
  A11yNode *holder = a11y_node(a11y_shown_holder(n));
  if (holder && holder->nid) a11y_place(holder, &hx, &hy);
  *x = (int)lround(ax - hx), *y = (int)lround(ay - hy), *w = (int)lround(n->w), *h = (int)lround(n->h);
  return TRUE;
}

static void a11y_obj_iface_init(GtkAccessibleInterface *iface) {
  iface->get_at_context = a11y_obj_context;
  iface->get_platform_state = a11y_obj_state;
  iface->get_accessible_parent = a11y_obj_parent;
  iface->get_first_accessible_child = a11y_obj_first;
  iface->get_next_accessible_sibling = a11y_obj_next;
  iface->get_bounds = a11y_obj_bounds;
}

G_DEFINE_TYPE_WITH_CODE(MBA11yObj, mb_a11y_obj, G_TYPE_OBJECT,
                        G_IMPLEMENT_INTERFACE(GTK_TYPE_ACCESSIBLE, a11y_obj_iface_init))

enum { A11Y_PROP_ROLE = 1 };

static void a11y_obj_get_property(GObject *o, guint id, GValue *v, GParamSpec *p) {
  if (id == A11Y_PROP_ROLE) g_value_set_enum(v, ((MBA11yObj *)o)->role);
  else G_OBJECT_WARN_INVALID_PROPERTY_ID(o, id, p);
}

static void a11y_obj_set_property(GObject *o, guint id, const GValue *v, GParamSpec *p) {
  if (id == A11Y_PROP_ROLE) ((MBA11yObj *)o)->role = g_value_get_enum(v);
  else G_OBJECT_WARN_INVALID_PROPERTY_ID(o, id, p);
}

static void a11y_obj_dispose(GObject *o) {
  g_clear_object(&((MBA11yObj *)o)->ctx);
  G_OBJECT_CLASS(mb_a11y_obj_parent_class)->dispose(o);
}

static void mb_a11y_obj_class_init(MBA11yObjClass *k) {
  GObjectClass *g = G_OBJECT_CLASS(k);
  g->get_property = a11y_obj_get_property;
  g->set_property = a11y_obj_set_property;
  g->dispose = a11y_obj_dispose;
  g_object_class_override_property(g, A11Y_PROP_ROLE, "accessible-role");
}

static void mb_a11y_obj_init(MBA11yObj *o) { (void)o; }

// what node `n` is, set on its accessible: its name, description, value and range, its state
static void a11y_obj_said(A11yNode *n) {
  GtkAccessible *a = GTK_ACCESSIBLE(n->obj);
  gtk_accessible_update_property(a, GTK_ACCESSIBLE_PROPERTY_LABEL, n->label, GTK_ACCESSIBLE_PROPERTY_DESCRIPTION,
                                 n->help, -1);
  if (n->range)
    gtk_accessible_update_property(a, GTK_ACCESSIBLE_PROPERTY_VALUE_MIN, n->low, GTK_ACCESSIBLE_PROPERTY_VALUE_MAX,
                                   n->high, GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, n->at, -1);
  if (*n->value) gtk_accessible_update_property(a, GTK_ACCESSIBLE_PROPERTY_VALUE_TEXT, n->value, -1);
  gtk_accessible_update_state(a, GTK_ACCESSIBLE_STATE_DISABLED, a11y_has(n->flags, 'd'), -1);
  if (a11y_has(n->flags, 'c'))
    gtk_accessible_update_state(a, GTK_ACCESSIBLE_STATE_CHECKED,
                                a11y_has(n->flags, 'C')   ? GTK_ACCESSIBLE_TRISTATE_TRUE
                                : a11y_has(n->flags, 'M') ? GTK_ACCESSIBLE_TRISTATE_MIXED
                                                          : GTK_ACCESSIBLE_TRISTATE_FALSE,
                                -1);
  if (a11y_has(n->flags, 'p'))
    gtk_accessible_update_state(a, GTK_ACCESSIBLE_STATE_PRESSED,
                                a11y_has(n->flags, 'P') ? GTK_ACCESSIBLE_TRISTATE_TRUE : GTK_ACCESSIBLE_TRISTATE_FALSE,
                                -1);
  if (a11y_has(n->flags, 'e')) gtk_accessible_update_state(a, GTK_ACCESSIBLE_STATE_EXPANDED, a11y_has(n->flags, 'E'), -1);
  if (a11y_has(n->flags, 's')) gtk_accessible_update_state(a, GTK_ACCESSIBLE_STATE_SELECTED, TRUE, -1);
}

static GObject *a11y_obj(int nid) {
  A11yNode *n = a11y_node(nid);
  if (!n || !nid) return NULL;
  if (!n->obj) {
    MBA11yObj *o = g_object_new(mb_a11y_obj_get_type(), "accessible-role", a11y_role(n->role), NULL);
    o->nid = nid;
    n->obj = G_OBJECT(o);
    a11y_obj_said(n);
  }
  return n->obj;
}

// The canvas: what it holds as accessibles, what the view holds (node 0's)
static GtkAccessible *canvas_first_accessible(GtkAccessible *self) {
  (void)self;
  return a11y_kid_after(0, 0);
}

static void canvas_accessible_init(GtkAccessibleInterface *iface) {
  GtkAccessibleInterface *parent = g_type_interface_peek_parent(iface);
  iface->get_at_context = parent->get_at_context;
  iface->get_platform_state = parent->get_platform_state;
  iface->get_accessible_parent = parent->get_accessible_parent;
  iface->get_next_accessible_sibling = parent->get_next_accessible_sibling;
  iface->get_bounds = parent->get_bounds;
  iface->get_first_accessible_child = canvas_first_accessible;
}

// Whether a screen reader runs (AT-SPI's bus: org.a11y.Status's ScreenReaderEnabled), followed: a frame asked for as
// it changes
static GDBusProxy *a11y_status;
static gboolean a11y_status_asked;

static void a11y_status_changed(GDBusProxy *p, GVariant *changed, GStrv gone, gpointer data) {
  (void)p, (void)changed, (void)gone, (void)data;
  schedule();
}

int32_t mb_host_a11y_on(void) {
  if (getenv("MBUI_A11Y_SELFCHECK")) return 1;
  if (!a11y_status_asked) {
    a11y_status_asked = TRUE;
    a11y_status = g_dbus_proxy_new_for_bus_sync(G_BUS_TYPE_SESSION, G_DBUS_PROXY_FLAGS_NONE, NULL, "org.a11y.Bus",
                                                "/org/a11y/bus", "org.a11y.Status", NULL, NULL);
    if (a11y_status) g_signal_connect(a11y_status, "g-properties-changed", G_CALLBACK(a11y_status_changed), NULL);
  }
  if (!a11y_status) return 0;
  GVariant *v = g_dbus_proxy_get_cached_property(a11y_status, "ScreenReaderEnabled");
  int on = v && g_variant_get_boolean(v);
  if (v) g_variant_unref(v);
  return on;
}

// MBUI_A11Y_SELFCHECK (see above): the canvas's accessibles walked as AT-SPI walks them, each said
static void a11y_walk(GtkAccessible *a, int depth, int *press) {
  for (GtkAccessible *c = gtk_accessible_get_first_accessible_child(a); c;) {
    if (G_TYPE_CHECK_INSTANCE_TYPE(c, mb_a11y_obj_get_type())) {
      A11yNode *n = a11y_node(((MBA11yObj *)c)->nid);
      int x, y, w, h;
      gboolean b = gtk_accessible_get_bounds(c, &x, &y, &w, &h);
      printf("A11Y node %s %s%s\n", n ? n->role : "?", n ? n->label : "", b ? "" : " (no bounds)");
      if (n && strcmp(n->label, "A11YCHECK press") == 0 && a11y_has(n->actions, 'a')) *press = n->widget;
    }
    if (depth < 32) a11y_walk(c, depth + 1, press);
    GtkAccessible *next = gtk_accessible_get_next_accessible_sibling(c);
    g_object_unref(c);
    c = next;
  }
}

static gboolean a11y_selfcheck(gpointer data) {
  (void)data;
  if (!area) return G_SOURCE_REMOVE;
  int press = 0;
  a11y_walk(GTK_ACCESSIBLE(area), 0, &press);
  printf("A11Y walked\n");
  fflush(stdout);
  // (the button pressed as a reader would ask it, were there a way for one: what it is asked comes to the app as on
  // the other hosts)
  if (press) {
    char json[64];
    int len = snprintf(json, sizeof json, "{\"id\":%d,\"action\":\"activate\"}", press);
    mb_post("a11y", json, (size_t)len, NULL, 0);
  }
  return G_SOURCE_REMOVE;
}

// What the widgets are now (@hostapi.a11y_tree): an update of them (a11y.mbt's head: the nodes that changed, each whole,
// and the focus), kept; one in nothing that holds it gone with what it holds; each told set on its accessible
void mb_host_a11y_tree(moonbit_string_t s) {
  char *all = utf8(s);
  gchar **lines = g_strsplit(all, "\n", -1);
  g_free(all);
  gchar **head = lines[0] ? g_strsplit(lines[0], "\x1f", -1) : NULL;
  if (!head || g_strv_length(head) < 3 || strcmp(head[0], "T") != 0) {
    g_strfreev(head), g_strfreev(lines);
    return;
  }
  gboolean full = strcmp(head[1], "1") == 0;
  int focus = atoi(head[2]);
  g_strfreev(head);
  if (!a11y_nodes) a11y_nodes = g_hash_table_new_full(g_direct_hash, g_direct_equal, NULL, a11y_node_free);
  if (full) g_hash_table_remove_all(a11y_nodes);
  GHashTable *held = g_hash_table_new(g_direct_hash, g_direct_equal);
  GArray *let_go = g_array_new(FALSE, FALSE, sizeof(int));
  GPtrArray *told = g_ptr_array_new();
  for (int i = 1; lines[i]; i++) {
    gchar **f = g_strsplit(lines[i], "\x1f", -1);
    if (g_strv_length(f) < 17 || strcmp(f[0], "N") != 0) {
      g_strfreev(f);
      continue;
    }
    A11yNode *n = g_new0(A11yNode, 1);
    n->nid = atoi(f[1]), n->role = g_strdup(f[2]), n->flags = g_strdup(f[3]);
    n->x = g_ascii_strtod(f[4], NULL), n->y = g_ascii_strtod(f[5], NULL);
    n->w = g_ascii_strtod(f[6], NULL), n->h = g_ascii_strtod(f[7], NULL);
    n->label = g_strdup(f[8]), n->value = g_strdup(f[9]), n->help = g_strdup(f[10]);
    n->range = f[12][0] != 0;
    n->low = g_ascii_strtod(f[11], NULL), n->at = g_ascii_strtod(f[12], NULL), n->high = g_ascii_strtod(f[13], NULL);
    n->actions = g_strdup(f[14]), n->widget = atoi(f[15]);
    n->kids = g_array_new(FALSE, FALSE, sizeof(int));
    if (f[16][0]) {
      gchar **ks = g_strsplit(f[16], ",", -1);
      for (int k = 0; ks[k]; k++) {
        int id = atoi(ks[k]);
        g_array_append_val(n->kids, id);
        g_hash_table_add(held, GINT_TO_POINTER(id));
      }
      g_strfreev(ks);
    }
    g_strfreev(f);
    A11yNode *o = a11y_node(n->nid);
    if (o) {
      n->parent = o->parent;
      for (guint k = 0; k < o->kids->len; k++) {
        int id = g_array_index(o->kids, int, k), kept = 0;
        for (guint j = 0; j < n->kids->len && !kept; j++) kept = g_array_index(n->kids, int, j) == id;
        if (!kept) g_array_append_val(let_go, id);
      }
      // (its accessible kept where its role is: what holds it on to it holds the same one)
      if (o->obj && strcmp(o->role, n->role) == 0) n->obj = g_steal_pointer(&o->obj);
    }
    g_hash_table_replace(a11y_nodes, GINT_TO_POINTER(n->nid), n);
    g_ptr_array_add(told, n);
  }
  g_strfreev(lines);
  for (guint i = 0; i < told->len; i++) {
    A11yNode *n = g_ptr_array_index(told, i);
    for (guint k = 0; k < n->kids->len; k++) {
      A11yNode *c = a11y_node(g_array_index(n->kids, int, k));
      if (c) c->parent = n->nid;
    }
  }
  // (one in nothing told holds: gone, with what it holds)
  while (let_go->len) {
    int k = g_array_index(let_go, int, let_go->len - 1);
    g_array_remove_index(let_go, let_go->len - 1);
    if (g_hash_table_contains(held, GINT_TO_POINTER(k))) continue;
    A11yNode *n = a11y_node(k);
    if (!n) continue;
    g_array_append_vals(let_go, n->kids->data, n->kids->len);
    g_hash_table_remove(a11y_nodes, GINT_TO_POINTER(k));
  }
  for (guint i = 0; i < told->len; i++) {
    A11yNode *n = g_ptr_array_index(told, i);
    if (n->obj) a11y_obj_said(n);
  }
  // (the focus as a platform state, read as AT-SPI asks: GTK 4.14 has nothing public to tell it moved of one that is
  // no widget)
  a11y_focus = focus;
  g_ptr_array_free(told, TRUE);
  g_array_free(let_go, TRUE);
  g_hash_table_destroy(held);
  if (getenv("MBUI_A11Y_SELFCHECK") && !a11y_selfcheck_done) {
    a11y_selfcheck_done = TRUE;
    g_idle_add(a11y_selfcheck, NULL);
  }
}
