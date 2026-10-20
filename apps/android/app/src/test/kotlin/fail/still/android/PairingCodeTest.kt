package fail.still.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PairingCodeTest {
    // The words of Android 16's pairing dialog, as an accessibility service reads them.
    private val dialog = listOf("Pair with device", "Wi‑Fi pairing code", "911073", "IP address & Port", "10.0.2.16:44005", "Cancel")

    @Test fun readsTheDialogsCode() = assertEquals("911073", pairingCode(dialog, 44005u))

    @Test fun spacedDigitsAreOneCode() = assertEquals("911073", pairingCode(dialog.map { if (it == "911073") " 911 073 " else it }, 44005u))

    @Test fun onlyInTheDialogOfThePortAnnounced() {
        assertNull(pairingCode(dialog, 44006u))
        assertNull(pairingCode(dialog, 4400u))
        // Wireless debugging's page behind it: its own port, no dialog.
        assertNull(pairingCode(listOf("Use wireless debugging", "IP address & Port", "10.0.2.16:36507", "Pair device with pairing code"), 44005u))
    }

    @Test fun notOneNumberNoCode() {
        assertNull(pairingCode(dialog + "123456", 44005u))
        assertNull(pairingCode(dialog.map { if (it == "911073") "91107" else it }, 44005u))
        assertNull(pairingCode(dialog.map { if (it == "911073") "Code 911073" else it }, 44005u))
    }
}
