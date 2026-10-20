// Reads the pairing dialog's code off Settings while 共享调试 pairs (docs/adb-share.md), so nobody types it: the dialog
// closes as soon as Settings is paused, a field popping up over it hides the code under the keyboard, and Settings hides
// other apps' windows over it. An accessibility service, as only one may read another app's window, turned on by the
// person (the 共享调试 page asks). It reads only Settings (res/xml/adb_code_reader.xml), only while a pairing port is
// announced for this app's share (AdbShare.pairingPort), and the code goes nowhere but the core's `adb.pair`, through
// AdbShareService, once per dialog.
package fail.still.android

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class AdbCodeReader : AccessibilityService() {
    private val scope = MainScope()
    /** The pairing port a code was read for: one try per dialog, a code that failed not tried again. */
    private var read: UInt? = null

    override fun onServiceConnected() {
        // The dialog is often open before its port is found (DNS-SD), and Settings says nothing more: looked at again then.
        scope.launch { AdbShare.pairingPort.collect { look() } }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = look()

    override fun onInterrupt() {}

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun look() {
        val port = AdbShare.pairingPort.value ?: return
        if (port == read) return
        val root = rootInActiveWindow ?: return
        val code = pairingCode(texts(root), port) ?: return
        read = port
        AdbShare.read(this, code, port)
    }

    /** The words a window shows, all of them (a dialog's are few). */
    private fun texts(root: AccessibilityNodeInfo): List<String> {
        val found = mutableListOf<String>()
        fun walk(node: AccessibilityNodeInfo, depth: Int) {
            node.text?.toString()?.let(found::add)
            if (depth < 32) for (i in 0 until node.childCount) node.getChild(i)?.let { walk(it, depth + 1) }
        }
        walk(root, 0)
        return found
    }
}

/**
 * The pairing dialog's code among a window's words: six digits (spaced or not), in the window that shows the pairing
 * port too (its IP address & port), so no other number on a Settings page is taken for it; none when it is not that one
 * or the digits are not one number.
 */
internal fun pairingCode(texts: List<String>, port: UInt): String? {
    val at = Regex(""":$port(?!\d)""")
    if (texts.none { at.containsMatchIn(it) }) return null
    val six = Regex("""\d(\s*\d){5}""")
    return texts.map(String::trim).filter(six::matches).map { it.filter(Char::isDigit) }.distinct().singleOrNull()
}
