// The settings' parts other pages use too: rows that go on, notes under a list, the pickers of a run (model, account,
// effort), a workspace's mark, a decision's options.
package fail.still.android.screens

import fail.still.android.ui.Spinner
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.shared.BuildConfig
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ConnectsView
import fail.still.android.data.ROLE_LABEL
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.WorkspaceView
import fail.still.android.data.errorText
import fail.still.android.data.rememberTopic
import fail.still.android.ui.Avatar
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.Seg
import fail.still.android.data.t
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import fail.still.android.ui.fileSize
import fail.still.android.ui.BusyIcon
import fail.still.android.ui.WaitLine
import fail.still.android.ui.WaitShape
import fail.still.android.ui.Waiting
import androidx.compose.foundation.background
import androidx.compose.ui.text.withStyle
import androidx.compose.foundation.layout.heightIn
import fail.still.android.ui.NavBar
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.style.TextAlign
import fail.still.android.AppState
import fail.still.android.data.ChatAgent
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatView
import fail.still.android.data.RunnableProfile
import fail.still.android.data.HistoryItem
import fail.still.android.data.HistoryBody
import fail.still.android.data.HistoryGroup
import fail.still.android.data.HistoryLive
import fail.still.android.data.HistoryPhase
import fail.still.android.data.HistoryStep
import fail.still.android.data.HistoryRow
import fail.still.android.data.HistoryView
import fail.still.android.data.ModelOption
import fail.still.android.data.ModelStation
import fail.still.android.data.PickBorrow
import fail.still.android.data.PickView
import fail.still.android.data.Host
import fail.still.android.data.AgentCardView
import fail.still.android.data.state
import fail.still.android.ui.MakerIcon
import fail.still.android.ui.ProviderMark
import fail.still.android.ui.QuotaChip
import fail.still.android.ui.QuotaRings
import fail.still.android.ui.NavButton
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import fail.still.android.ui.Mark
import fail.still.android.ui.Markdown
import fail.still.android.ui.MenuItem
import fail.still.android.ui.MenuSpec
import fail.still.android.ui.ModelMark
import fail.still.android.ui.Mono
import fail.still.android.ui.ReaderSpec
import fail.still.android.ui.MeterChips
import fail.still.android.ui.SlackMark
import fail.still.android.ui.Follow
import fail.still.android.ui.rememberFollow
import fail.still.android.ui.Smooth
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.animation.core.tween
import kotlinx.coroutines.delay
import fail.still.android.ui.DoingMark
import fail.still.android.ui.Field
import fail.still.android.ui.GroupLabel
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import android.content.Context
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.lazy.LazyItemScope
import androidx.compose.runtime.key
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.zIndex
import androidx.compose.foundation.Canvas
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import fail.still.android.ui.StationGlyph
import fail.still.android.ui.glyphCounts
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.layout.onSizeChanged
import fail.still.android.ui.floating
import fail.still.android.ui.glass
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.HazeState
import fail.still.android.data.Topic
import kotlin.math.roundToInt
import kotlin.math.abs
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import fail.still.android.ui.MoveSpring
import fail.still.android.ui.Ease
import androidx.compose.ui.unit.IntOffset
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.input.pointer.pointerInput
import fail.still.android.shared.R
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatState
import fail.still.android.data.badgeState
import fail.still.android.data.ChatsView
import fail.still.android.data.StatusView
import fail.still.android.data.WorkspaceMarksView
import fail.still.android.data.page
import fail.still.android.ui.Badge
import fail.still.android.ui.StationMark
import fail.still.android.ui.hasStationMark
import fail.still.android.ui.Illustration
import fail.still.android.ui.avatarColor
import fail.still.android.ui.initial
import androidx.compose.animation.AnimatedVisibility
import fail.still.android.ui.AgentStateMark
import androidx.compose.ui.res.painterResource
import androidx.compose.foundation.Image
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleOut
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.ui.unit.IntSize
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.material3.ripple
import fail.still.android.ui.keyboard
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.add
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.MutableIntState
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.util.lerp
import fail.still.android.data.ChatMessage
import fail.still.android.data.DecisionItem
import fail.still.android.data.DecisionOption
import fail.still.android.data.DecisionsView
import fail.still.android.data.Link
import fail.still.android.data.Me
import fail.still.android.ui.SMOOTH_SCALE
import fail.still.android.ui.WaitPill
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.net.toUri
import fail.still.android.data.Auth

/** A row that opens a page: its name, how things stand (`bad` in red; `dot`, a red dot before it), a chevron. */
@Composable
fun GoRow(title: String, value: String? = null, bad: Boolean = false, dot: Boolean = false, lead: (@Composable RowScope.() -> Unit)? = null, onClick: () -> Unit) {
    ListRow(onClick = onClick) {
        lead?.invoke(this)
        Text(title, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        if (value != null) Row(Modifier.widthIn(max = 220.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (dot) PresenceDot("error")
            Text(value, fontSize = 14.sp, color = if (bad) C.red else C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
    }
}

/** A page's note under its title, in a line or two. */
@Composable
fun PageNote(text: String) = Text(text, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 10.dp))

/** A line that leads to a list: what is chosen, and an arrow. */
@Composable
fun SettingRow(onClick: () -> Unit, leading: @Composable () -> Unit = {}, content: @Composable ColumnScope.() -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(Smooth(12.dp)).background(C.chip).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        leading()
        Column(Modifier.weight(1f), content = content)
        IconIn(Icons.ChevronRight, 16.dp, C.muted)
    }
}

/** Every model it can move to, by series (the core says); a filter once there are many. */
@Composable
fun ModelList(models: List<ModelOption>, runtime: String, picked: String?, onPick: (String) -> Unit) {
    var filter by remember { mutableStateOf("") }
    val shown = models.filter { m -> (listOf(m.name, m.model) + m.ids).any { it.contains(filter.trim(), ignoreCase = true) } }
    val on = models.optionOf(picked)
    // By series, in the core's order.
    val groups = shown.groupBy { it.family ?: t("android-chat.pick.family.other") }
    Column(Modifier.fillMaxSize().padding(horizontal = 18.dp)) {
        if (models.size > 8) Field(filter, { filter = it }, t("android-chat.run.model.search"), modifier = Modifier.padding(top = 8.dp, bottom = 4.dp))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            groups.forEach { (who, list) ->
                if (groups.size > 1) GroupLabel(who)
                list.forEach { m ->
                    // Not usable here till borrowed: faint, its station too, until it is the one picked.
                    val faint = m.availability == "borrowable" && m != on
                    PickLine(m.name, checked = m == on, onClick = { onPick(m.model) }, leading = { MakerIcon(m.maker, runtime, 18.dp) }, faint = faint,
                        tag = m.fromStation?.let { from -> { ModelFrom(from, m.fromText, faint) } })
                }
            }
            if (shown.isEmpty()) Text(t("android-chat.run.model.none"), fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(vertical = 16.dp))
            Box(Modifier.windowInsetsPadding(WindowInsets.navigationBars).height(16.dp))
        }
    }
}

/** Who can run the model picked: the station's pick, or one kept to, with its quota. */
@Composable
fun AccountList(accounts: List<RunnableProfile>, runtime: String, picked: String?, onPick: (String?) -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp)) {
        Text(t("android-chat.run.account.note"), fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(top = 8.dp, bottom = 4.dp))
        PickLine(t("android-chat.run.account.auto"), checked = picked == null, onClick = { onPick(null) })
        accounts.forEach { p ->
            PickLine(p.name, checked = picked == p.id, onClick = { onPick(p.id) },
                leading = { ProviderMark(p.runtime ?: runtime, p.kind, 18.dp, p.mark) }, trailing = { QuotaRings(p.quota) })
        }
        Box(Modifier.windowInsetsPadding(WindowInsets.navigationBars).height(16.dp))
    }
}

/** How hard it thinks, as chips as wide as their words, wrapping when they do not fit a line. */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun EffortChips(efforts: List<String?>, picked: String?, onPick: (String?) -> Unit) {
    androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        efforts.forEach { e ->
            val on = e == picked
            Text(
                e ?: t("android-chat.pick.default"), fontSize = 14.sp, color = if (on) C.bg else C.ink, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal,
                modifier = Modifier.clip(Smooth(18.dp)).background(if (on) C.ink else C.chip).clickable { onPick(e) }.padding(horizontal = 16.dp, vertical = 9.dp),
            )
        }
    }
}

/**
 * What a workspace has waiting, as the core says (views/marks.ts): `alert` a red dot with a soft halo, `wait` a blue
 * ring (a card or an agent waits on them), `done` a blue dot; as a chat's mark (ChatMark), still. `label` says it in words.
 */
@Composable
fun WorkspaceMark(tone: String, label: String) {
    Canvas(Modifier.size(10.dp).semantics { contentDescription = label }) {
        val r = size.minDimension / 2 - 1.dp.toPx()
        val ring = 2.dp.toPx()
        if (tone == "alert") drawCircle(MarkRed.copy(alpha = 0.25f), r + 3.dp.toPx())
        if (tone == "wait") drawCircle(MarkBlue, 4.5.dp.toPx() - ring / 2, style = Stroke(ring))
        else drawCircle(if (tone == "alert") MarkRed else MarkBlue, r)
    }
}

/**
 * What a workspace has waiting, after its name in the switcher (web: ChatMark.tsx MarkCounts): a red dot and how many
 * of the chats its person takes part in want them, a blue ring and how many wait on them, a blue dot and how many are
 * unread; nothing for none.
 */
@Composable
fun MarkCounts(mark: fail.still.android.data.WorkspaceMark) {
    if (mark.tone == null) return
    Row(Modifier.semantics(mergeDescendants = true) { contentDescription = mark.label.orEmpty() }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf("alert" to mark.alert, "wait" to (mark.wait ?: 0u), "done" to mark.unread).filter { it.second > 0u }.forEach { (tone, n) ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                WorkspaceMark(tone, "")
                Text("$n", fontSize = 12.sp, color = C.muted)
            }
        }
    }
}

/**
 * A decision's options (web Decisions.tsx DecisionOptions): one card, full width, a row each — its number in a circle,
 * the label (medium) and its detail under it, small and quiet, a hairline between two. The recommended one (last, as
 * the core orders them) is told by its number in the accent alone (said to a screen reader). `busy`: the label of the one being sent
 * (a spinner on it, none pressed meanwhile).
 */
@Composable
fun DecisionOptions(options: List<DecisionOption>, modifier: Modifier = Modifier, enabled: Boolean = true, busy: String? = null, onPick: (DecisionOption) -> Unit) {
    val hairline = C.ink.copy(alpha = 0.07f)
    // A card of rows to be pressed (web pages.css.ts listCard, docs/ui-panels.md 页面卡片): each row's ground under the
    // finger OPTION_PAD from the card's edge, rounded OPTION_CORNER, the card's corner theirs and that together; its
    // number in its row's corner, concentric with it; its words OPTION_WORDS from the card's edge, as a card of words'.
    Column(modifier.fillMaxWidth().clip(Smooth(OPTION_CORNER + OPTION_PAD / SMOOTH_SCALE)).background(C.chip).padding(OPTION_PAD)) {
        options.forEachIndexed { i, o ->
            val strong = o.recommended == true
            val said = if (strong) t("common.recommended") else null
            val free = enabled && busy == null
            if (i > 0) Box(Modifier.padding(start = NUMBER_IN + NUMBER + 12.dp, end = OPTION_WORDS - OPTION_PAD).fillMaxWidth().height(1.dp).background(hairline))
            Row(
                Modifier.fillMaxWidth().clip(Smooth(OPTION_CORNER)).alpha(if (enabled) 1f else 0.5f)
                    .clickable(enabled = free, interactionSource = remember(o.label) { MutableInteractionSource() }, indication = ripple(color = C.ink)) { onPick(o) }
                    .padding(start = NUMBER_IN, end = OPTION_WORDS - OPTION_PAD, top = NUMBER_IN, bottom = NUMBER_IN)
                    .semantics(mergeDescendants = true) { said?.let { stateDescription = it } },
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(
                    Modifier.size(NUMBER).clip(CircleShape).background(if (strong) C.accent else C.ink.copy(alpha = 0.09f)),
                    contentAlignment = Alignment.Center,
                ) {
                    val ink = if (strong) Color.White else C.muted
                    Digits.getOrNull(i)?.let { IconIn(it, NUMBER, ink) }
                        ?: Text("${i + 1}", fontSize = 12.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold, color = ink)
                }
                Column(Modifier.weight(1f)) {
                    Text(o.label, fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Medium, color = C.ink)
                    o.detail?.let { Text(it, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted) }
                }
                if (busy == o.label) DoingMark(true, null, inline = true)
            }
        }
    }
}

/**
 * Borrowing the picked model's account from the station that has it (a model control's `borrow`), asked again first:
 * the stations differ. Its title, each of its lines, then `pick.borrow`; a toast says it is borrowed.
 */
fun confirmBorrow(app: AppState, station: String, of: String, borrow: PickBorrow) =
    confirm(app, borrow.title, borrow.lines.joinToString("\n\n"), borrow.action) {
        app.api(station).pickBorrow(of)
        app.toast = t("android-chat.run.borrowed")
    }

/** The option a model is, however it is spelled (openai/gpt-6-astra is gpt-6-astra). */
fun List<ModelOption>.optionOf(model: String?): ModelOption? =
    if (model == null) null else firstOrNull { it.model == model } ?: firstOrNull { model in it.ids }

/**
 * Where a model of another station comes from, after its name on the same line (web ModelTriple's runOptionFrom):
 * the station's mark where it has one, else its name, small and muted; said as `text` (借自 Studio, 在 Studio 上).
 * `faint`: not usable here till borrowed, at half.
 */
@Composable
fun ModelFrom(from: ModelStation, text: String?, faint: Boolean = false) {
    Box(Modifier.alpha(if (faint) 0.5f else 1f).semantics { contentDescription = text ?: from.name }) {
        if (hasStationMark(from.emoji, from.icon)) StationMark(from.emoji, from.icon, 14.dp, C.muted)
        else Text(from.name, fontSize = 12.sp, color = C.muted, maxLines = 1, softWrap = false)
    }
}

/**
 * A choice in a list: what it is, a note under it, and a check when it is the one chosen. `tag`: after the label, on
 * its line (a model's station); `faint`: the label muted (a model not usable here till borrowed).
 */
@Composable
fun PickLine(label: String, sub: String? = null, checked: Boolean, onClick: () -> Unit, leading: (@Composable () -> Unit)? = null, trailing: (@Composable () -> Unit)? = null, tag: (@Composable () -> Unit)? = null, faint: Boolean = false) {
    Row(
        Modifier.fillMaxWidth().clip(Smooth(10.dp)).clickable(onClick = onClick).padding(horizontal = 4.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        leading?.invoke()
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(label, fontSize = 15.sp, color = if (faint) C.muted else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                tag?.invoke()
            }
            if (sub != null) Text(sub, fontSize = 12.sp, color = C.muted)
        }
        trailing?.invoke()
        Box(Modifier.width(18.dp), contentAlignment = Alignment.Center) { if (checked) IconIn(Icons.Check, 16.dp, C.accent) }
    }
}

val MarkBlue = Color(0xFF3B82F6)

val MarkRed = Color(0xFFE5484D)

/** Each option's number, drawn (scripts/option-digits.py: in the middle of its circle at any size); past six, set. */
val Digits = listOf(Icons.Option1, Icons.Option2, Icons.Option3, Icons.Option4, Icons.Option5, Icons.Option6)

val OPTION_PAD = 8.dp

val OPTION_CORNER = 18.dp

val OPTION_WORDS = 20.dp

val NUMBER = 22.dp

/** The number in its row's corner: the row's corner less its half (both as round as they are drawn: Smooth's is round 18). */
val NUMBER_IN = OPTION_CORNER - NUMBER / 2

/** Starts a Google sign-in through still.fail cloud in a Custom Tab; MainActivity finishes it when stillfail://auth/callback comes back. */
suspend fun signIn(app: AppState, context: Context) {
    try {
        val url = Auth.begin(app.core)
        CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, url.toUri())
    } catch (e: CoreException) {
        app.toast = t("android-settings.signIn.beginFailed", "error" to e.message)
    }
}
