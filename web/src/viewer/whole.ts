// The app's reader and player told to the file preview (FilePreview.tsx setWholeViewers): a text and a video a chat
// has open in them, as a station's file does. Imported by what starts the app (main.tsx, the site's demo, the
// stories), never by a page with no core (a published chat's).
import { setWholeViewers } from "../FilePreview.tsx";
import { Reader } from "../drive/Reader.tsx";
import { Player } from "../drive/Player.tsx";

setWholeViewers({ Reader, Player });
