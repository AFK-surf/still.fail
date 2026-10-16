// What a person does on the phone, as a station's screen takes it (docs/remote-screens.md, `screen.input`): points in
// 0..1 of the frame, buttons as the DOM's bit mask, keys by the DOM's KeyboardEvent names, typed text as it is committed.
package fail.still.android.remote

import android.content.Context
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** The DOM's mouse buttons (MouseEvent.buttons). */
internal const val PRIMARY = 1
internal const val SECONDARY = 2

/**
 * Where `p` (on the stage) is on the frame drawn at `shown` (on the stage too: letterboxed, zoomed), 0..1 each way.
 * Outside the frame: null, or the nearest edge when `clamp` (a drag that went past it).
 */
internal fun frameAt(p: Offset, shown: Rect, clamp: Boolean): Offset? {
    if (shown.width <= 0f || shown.height <= 0f) return null
    val x = (p.x - shown.left) / shown.width
    val y = (p.y - shown.top) / shown.height
    if (!clamp && (x < 0f || x > 1f || y < 0f || y > 1f)) return null
    return Offset(x.coerceIn(0f, 1f), y.coerceIn(0f, 1f))
}

/** Where a frame of `frame` px fits whole in a stage of `box` px, centred (letterboxed). */
internal fun fitIn(box: androidx.compose.ui.geometry.Size, frame: androidx.compose.ui.geometry.Size): Rect {
    if (frame.width <= 0f || frame.height <= 0f || box.width <= 0f || box.height <= 0f) return Rect.Zero
    val k = minOf(box.width / frame.width, box.height / frame.height)
    val w = frame.width * k
    val h = frame.height * k
    val left = (box.width - w) / 2
    val top = (box.height - h) / 2
    return Rect(left, top, left + w, top + h)
}

internal fun pointer(kind: String, at: Offset, buttons: Int): JsonObject = buildJsonObject {
    put("t", "pointer"); put("kind", kind); put("x", at.x.toDouble()); put("y", at.y.toDouble()); put("buttons", buttons)
}

/** A wheel at `at`, `dx`/`dy` in CSS pixels (positive: scrolls right / down). */
internal fun wheel(at: Offset, dx: Float, dy: Float): JsonObject = buildJsonObject {
    put("t", "wheel"); put("x", at.x.toDouble()); put("y", at.y.toDouble()); put("dx", dx.toDouble()); put("dy", dy.toDouble())
}

internal fun key(kind: String, key: String, code: String, mods: Int): JsonObject = buildJsonObject {
    put("t", "key"); put("kind", kind); put("key", key); put("code", code); put("mods", mods)
}

internal fun text(text: String): JsonObject = buildJsonObject { put("t", "text"); put("text", text) }

/** Android's modifier keys as the station takes them: bit 0 Alt, 1 Ctrl, 2 Meta, 3 Shift. */
internal fun mods(meta: Int): Int =
    (if (meta and KeyEvent.META_ALT_ON != 0) 1 else 0) or
        (if (meta and KeyEvent.META_CTRL_ON != 0) 2 else 0) or
        (if (meta and KeyEvent.META_META_ON != 0) 4 else 0) or
        (if (meta and KeyEvent.META_SHIFT_ON != 0) 8 else 0)

/** The keys that are not text, by Android's key code: the DOM's `key` and `code`. */
private val NAMED = mapOf(
    KeyEvent.KEYCODE_ENTER to ("Enter" to "Enter"),
    KeyEvent.KEYCODE_NUMPAD_ENTER to ("Enter" to "NumpadEnter"),
    KeyEvent.KEYCODE_DEL to ("Backspace" to "Backspace"),
    KeyEvent.KEYCODE_FORWARD_DEL to ("Delete" to "Delete"),
    KeyEvent.KEYCODE_TAB to ("Tab" to "Tab"),
    KeyEvent.KEYCODE_ESCAPE to ("Escape" to "Escape"),
    KeyEvent.KEYCODE_DPAD_LEFT to ("ArrowLeft" to "ArrowLeft"),
    KeyEvent.KEYCODE_DPAD_RIGHT to ("ArrowRight" to "ArrowRight"),
    KeyEvent.KEYCODE_DPAD_UP to ("ArrowUp" to "ArrowUp"),
    KeyEvent.KEYCODE_DPAD_DOWN to ("ArrowDown" to "ArrowDown"),
    KeyEvent.KEYCODE_MOVE_HOME to ("Home" to "Home"),
    KeyEvent.KEYCODE_MOVE_END to ("End" to "End"),
    KeyEvent.KEYCODE_PAGE_UP to ("PageUp" to "PageUp"),
    KeyEvent.KEYCODE_PAGE_DOWN to ("PageDown" to "PageDown"),
    KeyEvent.KEYCODE_SPACE to (" " to "Space"),
)

/**
 * A key as the DOM names it (`key`, `code`): the named ones above; a letter or digit with Ctrl, Alt or Meta held (a
 * shortcut: Ctrl+C) by its character. Null for the rest: plain characters go as text.
 */
internal fun domKey(keyCode: Int, char: Int, meta: Int): Pair<String, String>? {
    NAMED[keyCode]?.let { return it }
    val shortcut = meta and (KeyEvent.META_CTRL_ON or KeyEvent.META_ALT_ON or KeyEvent.META_META_ON) != 0
    if (!shortcut) return null
    return when (keyCode) {
        in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z -> {
            val c = 'a' + (keyCode - KeyEvent.KEYCODE_A)
            (if (meta and KeyEvent.META_SHIFT_ON != 0) c.uppercase() else c.toString()) to "Key${c.uppercaseChar()}"
        }
        in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> {
            val c = '0' + (keyCode - KeyEvent.KEYCODE_0)
            c.toString() to "Digit$c"
        }
        else -> if (char > 0) String(Character.toChars(char)) to "" else null
    }
}

/**
 * An unseen view that takes the keyboard (the system's IME, or one plugged in) for the screen: what is typed and
 * committed goes as text, Enter / Backspace / arrows and shortcuts as keys. It keeps nothing itself: there is no text
 * here to edit, the station's is.
 */
internal class KeyCatcher(context: Context, private val send: (JsonObject) -> Unit) : View(context) {
    init {
        isFocusable = true
        isFocusableInTouchMode = true
    }

    override fun onCheckIsTextEditor() = true

    override fun onCreateInputConnection(out: EditorInfo): InputConnection {
        out.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        out.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_FULLSCREEN or EditorInfo.IME_ACTION_NONE
        return Connection()
    }

    /** Types `s`: lines as text, Enter between them. */
    private fun type(s: CharSequence) {
        s.toString().split('\n').forEachIndexed { i, line ->
            if (i > 0) tap("Enter", "Enter", 0)
            if (line.isNotEmpty()) send(text(line))
        }
    }

    private fun tap(k: String, code: String, mods: Int) {
        send(key("down", k, code, mods))
        send(key("up", k, code, mods))
    }

    /** A key event (from the IME or a keyboard): named keys and shortcuts as keys, characters as text. */
    private fun press(event: KeyEvent): Boolean {
        val kind = when (event.action) { KeyEvent.ACTION_DOWN -> "down"; KeyEvent.ACTION_UP -> "up"; else -> return false }
        val named = domKey(event.keyCode, event.unicodeChar, event.metaState)
        if (named != null) {
            send(key(kind, named.first, named.second, mods(event.metaState)))
            return true
        }
        val char = event.unicodeChar
        if (char > 0) {
            if (kind == "down") send(text(String(Character.toChars(char))))
            return true
        }
        return false
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean =
        if (keyCode == KeyEvent.KEYCODE_BACK) super.onKeyDown(keyCode, event) else press(event) || super.onKeyDown(keyCode, event)

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean =
        if (keyCode == KeyEvent.KEYCODE_BACK) super.onKeyUp(keyCode, event) else press(event) || super.onKeyUp(keyCode, event)

    private inner class Connection : BaseInputConnection(this, false) {
        /** What the IME is composing (a word, pinyin): typed once it is committed or finished. */
        private var composing = ""

        override fun commitText(text: CharSequence, newCursorPosition: Int): Boolean {
            composing = ""
            type(text)
            return true
        }

        override fun setComposingText(text: CharSequence, newCursorPosition: Int): Boolean {
            composing = text.toString()
            return true
        }

        override fun finishComposingText(): Boolean {
            if (composing.isNotEmpty()) type(composing)
            composing = ""
            return true
        }

        override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
            if (composing.isNotEmpty()) {
                composing = composing.dropLast(beforeLength)
                return true
            }
            repeat(beforeLength) { tap("Backspace", "Backspace", 0) }
            repeat(afterLength) { tap("Delete", "Delete", 0) }
            return true
        }

        override fun sendKeyEvent(event: KeyEvent): Boolean = press(event)

        override fun performEditorAction(actionCode: Int): Boolean {
            tap("Enter", "Enter", 0)
            return true
        }
    }
}
