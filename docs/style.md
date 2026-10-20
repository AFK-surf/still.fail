# Styles

What a box or a line of words looks like is a value, named, made of the theme's tokens, and given to the call that
builds it:

```moonbit
let card : @ui.Style = @ui.style(w=Full, p=S5, radius=Xl3, bg=Card, pressed=@ui.patch(bg=Over(Card, A(Fg, O5))))
c.box(style=card, id=c.id("row"), fn() { … })
c.text(title, style=@sf.title)
c.rich(runs, style=@sf.body)
```

`src/ui/style_tokens.mbt` has the tokens, `src/ui/style.mbt` the values, `src/kit/styles.mbt` kit's recipes.

## Tokens

A style says names, not numbers. The numbers are in the theme (`Theme`, set with `Ctx::set_theme`), looked up as the
node is built, so one style is a constant and right in light and dark, wide and narrow.

| token | names | values |
|---|---|---|
| `Space` (padding, gaps) | `S0` `SPx` `S0_5` `S1` … `S12` `S14` `S16` `S20` … `S96` | Tailwind v3.4's: a step 4 px |
| `Len` (sizes) | `Hug` (what it holds), `Full`, `Grow(k)`, `Fixed(v)`, and every `Space` name | |
| `Radius` | `Sharp` `Sm` `Base` `Md` `Lg` `Xl` `Xl2` `Xl3` `Full` (a pill) `Inner` | `Theme.radii` (Tailwind's by default) |
| `TextSize` (size and line) | `Xs` `Sm` `Base` `Lg` `Xl` `Xl2` `Xl3` `Xl4` | `Theme.text` (Tailwind's by default) |
| `Weight` | `Normal` `Medium` `Semibold` `Bold` | 400 … 700 |
| `Color` | `Bg` `Surface` `Raised` `Card` `Fg` `Muted` `Subtle` `Faint` `Line` `Border` `Accent` `AccentText` `AccentBg` `OnAccent` `Primary` `OnPrimary` `Positive` `Danger` `DangerBg` `OnDanger` `Neutral` `Hover` `Selected` `Focus` `Scrim` `Link` `ShadowC` `Clear`; `A(c, o)` at an opacity, `Over(under, top)` | the theme's fields |
| `Opacity` | `O0` `O5` … `O95` `O100` | |
| `Stroke` (an edge) | `B0` `B1` `B2` `B4` `B8` | |
| `Shadow` | `NoShadow` `Sm` `Base` `Md` `Lg` `Xl` | Tailwind's first layer, in `Theme.shadow` |

`Exact(…)` is a value off the scale. It belongs in an app's token file (detlint's `style.tokens`), named:
`pub let code_size : @ui.TextSize = Exact(13.0, 0.0)`. Out of the scale's bounds (below 0, an opacity past 1) it
stops the frame, saying what it was.

Outside a style: `c.space(S11)`, `c.color(Fg)`, `c.text_size(Sm)`.

## The theme, wide and narrow

`c.set_theme(wide, narrow=…, narrow_below=700.0)` once, as the app starts and when the person picks light or dark.
Each frame, before it builds, the window's width picks the one in force (`Ctx::narrow`). `c.with_theme(t, body)` puts
another under part of a view.

## Properties

A box: `row`, `w` `h` `min_w` `max_w` `min_h` `max_h`, `p` `px` `py` `pl` `pr` `pt` `pb`, `gap`, `align`, `justify`,
`bg`, `radius`, `border`, `border_color`, `shadow`, `clip`, `opacity`. Words: `size` (with its line), `weight`, `color`,
`w`, `center`, `wrap` (false: one line, cut with an ellipsis). Behaviour is not a style (`id`, `glass`, `notch_*`,
`aspect`, `tx`/`ty`).

`radius=Inner`: the corner of the container the corner rule measures against (`Tester::corner_faults`: the nearest
rounded one round it that shows, through boxes with no corner, or a ground laid beside it as a layer) less how far the
box lies from that container's edges it is near, as laid out. What lies in a rounded container's corner is concentric
with it by how it is written. Where it cannot be (in no rounded container, near none of its edges, nearer one edge than
another: the window narrowed, a `max_w` came into force) it is drawn square and `corner_faults` says so: a test fails,
a person's screen does not stop.

## The three rules

1. In one `style(…)` each property is said once. Padding from the finer to the coarser: `pl` `pr` `pt` `pb` over
   `px` `py` over `p`.
2. `a.then(b)`: what `b` says over `a`; `b`'s coarser padding takes `a`'s finer with it (`b`'s `px` drops `a`'s `pl`
   and `pr`); their state blocks merge the same way. A recipe is base, then its variants, then their compounds; what
   the call says loosely (`pad=`, `bg=`, `size=`) last.
3. A node's states are laid on in one order, the later winning: `narrow`, `dark`, `selected`, `hovered`, `focused`,
   `pressed`, `disabled`. `pressed`, `hovered`, `focused` come from the box's `id` (`Ctx::pressed`, `hovered`,
   `focus_shown`: the inputs the last frame took); `selected`, `disabled` are said in the call; `dark` is the theme's,
   `narrow` the width's. Words have `dark` and `narrow` alone.

Nothing cascades: no selectors, words do not inherit from the boxes round them. Nothing in a style moves by itself
(no transition): a state changed is the other value from the frame that sees it. An animation is motion's.

## kit's recipes

`card(tone)`, `list_card()`, `list_row(density)`, `section_header(indent)`, `button_style(size, tone)` with
`button_text`, `field(size)`, `badge(tone)` with `badge_text`, `panel()`; words `row_title`, `row_sub`, `row_value`,
`section_title`. Tokens alone: an app's theme is their look. What does not fit goes in the app's own styles.

## The lint

detlint (docs/detlint.md) counts, file by file, only going down:

- `style-literal`: a number in a box's or words' look (`c.box(pad=12.0)`, `c.text(size=13.0)`), in `@ui.style(…)`
  and its kin, or an `Exact(…)` outside the token files;
- `box-loose`: a call that says its look loosely (`pad=`, `bg=`, `size=`…) rather than by `style=`;
- `style-exact`: every `Exact(…)`, the token files' too.

`Tester::census()` gives the values the last frame used, by kind (sizes of words, weights, paddings, corners,
colours): an app counts how many each kind has across its screens, which should go down.
