// What a page of one module shows or opens of another's (:settings, :chat, :drive stand side by side, none seeing the
// others): the app says what each is as it starts (App.kt StillFailApp); before that, nothing.
package fail.still.android.screens

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import fail.still.android.AppState
import fail.still.android.data.Overview
import fail.still.android.data.WorkspaceEntry

object Elsewhere {
    // The settings' (:settings), for the chats' pages.
    /** A station's card over the page (Stations.kt openStationPeek). */
    var stationPeek: (app: AppState, address: String) -> Unit = { _, _ -> }
    /** The workspaces' switcher (Workspaces.kt openWorkspaces). */
    var workspaces: (app: AppState) -> Unit = {}
    /** Whether invitations wait for the person (Workspaces.kt invitationsWaiting). */
    var invitationsWaiting: @Composable (app: AppState) -> Boolean = { false }
    var firstStation: @Composable (current: WorkspaceEntry) -> Unit = {}
    var machineLoginOffers: @Composable (station: String, overview: Overview, inset: Dp) -> Unit = { _, _, _ -> }
    var vaultApproval: @Composable (workspace: String, request: String, mine: Boolean, modifier: Modifier) -> Unit = { _, _, _, _ -> }

    // The chats' (:chat), for the drive's pages.
    /** A file over the page in the chat's viewer (FilePreview.kt); `folder`: the pictures it steps through. */
    var preview: @Composable (station: String, shown: Shown, folder: (() -> List<Shown>)?, onClose: () -> Unit) -> Unit = { _, _, _, _ -> }

    /** What to do when a station has none yet (Settings.kt FirstStation). */
    @Composable fun FirstStation(current: WorkspaceEntry) = firstStation(current)
    /** A station's machine logins to offer (Profiles.kt MachineLoginOffers). */
    @Composable fun MachineLoginOffers(station: String, overview: Overview, inset: Dp = 12.dp) = machineLoginOffers(station, overview, inset)
    /** A vault request's approval (Vault.kt VaultApproval). */
    @Composable fun VaultApproval(workspace: String, request: String, mine: Boolean, modifier: Modifier = Modifier) = vaultApproval(workspace, request, mine, modifier)
}
