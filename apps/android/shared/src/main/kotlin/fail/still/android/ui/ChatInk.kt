// The chats' own colours and a station's name, as the chat draws them and the pages beside it say them; here so
// that those pages need not depend on the chat (2026-10-17).
package fail.still.android.ui

import fail.still.android.ui.Spinner
import fail.still.android.ui.WaitShape
import fail.still.android.ui.Waiting
import fail.still.android.data.t
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.togetherWith
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.ui.graphics.compositeOver
import fail.still.android.ui.letsGoOfKeyboard
import fail.still.android.ui.MakerIcon
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ActivityNow
import fail.still.android.data.AgentWait
import fail.still.android.data.Attachment
import fail.still.android.data.ChatAgent
import fail.still.android.data.ChatJobsView
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatSentElsewhere
import fail.still.android.data.ChatView
import fail.still.android.data.Maker
import fail.still.android.data.Live
import fail.still.android.data.ChatMessage
import fail.still.android.data.Outgoing
import fail.still.android.data.Quote
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceView
import fail.still.android.data.rememberTopic
import fail.still.android.data.errorText
import fail.still.android.data.state
import fail.still.android.ui.Avatar
import fail.still.android.ui.C
import fail.still.android.ui.LocalTextMark
import fail.still.android.ui.middleIn
import fail.still.android.ui.passageMark
import fail.still.android.ui.Ease
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Mark
import fail.still.android.ui.Markdown
import fail.still.android.ui.SlackMark
import fail.still.android.ui.MenuItem
import fail.still.android.ui.MenuSpec
import fail.still.android.ui.ModelMark
import fail.still.android.ui.NavButton
import fail.still.android.ui.PeopleStack
import fail.still.android.ui.awayFromEnd
import fail.still.android.ui.endInView
import fail.still.android.ui.floating
import fail.still.android.ui.glass
import fail.still.android.ui.rememberFollow
import fail.still.android.ui.Smooth
import fail.still.android.ui.drawSmooth
import fail.still.core.CoreException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import fail.still.android.ui.DoingMark

/** The station part of an address ("ws/studio" → "studio"). */
fun stationName(address: String) = address.substringAfter('/')
/** A station's name in its workspace. */
@Composable
fun rememberStationName(station: String): String {
    val app = LocalApp.current
    val ws by rememberTopic<WorkspaceView>(app.core, Topics.workspace(station.substringBefore('/')))
    return ws.value?.stations?.firstOrNull { it.id == stationName(station) }?.name ?: stationName(station)
}

/**
 * The chat's own colours, as web mobile draws its messages: with the wide screen's tokens (web/src/styles/global.css.ts,
 * inside mobile/styles/root.css.ts → wide), over the phone's paper; neutral is the phone's bubble (--m-bubble, Theme.kt bubble).
 */
class ChatInk(
    val text: Color, val muted: Color, val subtle: Color, val neutral: Color, val name: Color, val card: Color,
    val accent: Color, val amber: Color, val canvas: Color,
)
private val LightInk = ChatInk(
    text = Color(0xFF24272B), muted = Color(0xFF646970), subtle = Color(0xFF73787D), neutral = Color(0xFFE8E4DC), name = Color(0xFFA23203),
    card = Color(0xFFF6F6F7), accent = Color(0xFFEF6A3C), amber = Color(0xFF7F5306), canvas = Color(0xFFFFFFFF),
)
private val DarkInk = ChatInk(
    text = Color(0xFFE9E9EA), muted = Color(0xFFA3A5A9), subtle = Color(0xFF8C8F94), neutral = Color(0xFF313237), name = Color(0xFFFC9B6F),
    card = Color(0xFF27282B), accent = Color(0xFFF57E4D), amber = Color(0xFFE6B55D), canvas = Color(0xFF1F2023),
)
@Composable
fun chatInk(): ChatInk = if (C.dark) DarkInk else LightInk
@Composable
fun chatMuted() = chatInk().muted
@Composable
fun chatSubtle() = chatInk().subtle
/** A quote's card: the ink faint over the canvas. */
@Composable
fun quoteGround() = chatInk().card

/** Whether the screen is wide (App.kt Pages): Home leaves its new-chat button to WideCorners then, the composer room for Recent. */
val LocalWide = androidx.compose.runtime.staticCompositionLocalOf { false }
