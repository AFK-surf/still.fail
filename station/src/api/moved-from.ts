// The first build that takes a workspace whose chain moved to its people's own logs whole, read as it moved beside those
// logs (rules/src/lock/state4.mbt `state4_moved`, 2026-11-14: what the logs have not said yet of someone the chain named,
// the chain as it moved still says): every reader must make the same state of the same chain, logs and bodies, so a
// release before it (#6070's, 9008 on, read the logs alone) is told to update at a moved workspace and a handover waits
// for every app device the chain lets in to run one. A station or app of a release before 9008 refuses a chain or a
// person's log holding `moved`, `ws` or `web` (rules/AGENTS.md). Read by the station (a core of a counted build under it
// told to update where a chain moved, mesh/serve.ts) and by the core (a handover waits for every app device the chain
// lets in to run one, client/core-ts src/lock-handover.ts): nothing else here, so the core takes this file as it is.
//
// 9144: the build after the commit on main that brings a carried member's own `bind` and the rule between two of them to
// the station and the core (rules/src/lock/roster.mbt `binds_of`; #6217, main's build 9143), never below it: a number
// under that commit would take a build without this code as able. (9100 before, for `state4_moved` alone, under which
// no app moved a chain: they were held; 9170 for the eighteen commits after the hold went, set before #6217's build was
// known, which kept the builds that took the hold out, 9153 on, from moving anything until main reached it: a wait
// nothing needed.) A build from 9144 to 9152 reads a moved chain whole and still holds its own back.
export const MOVED_FROM_BUILD = 9144;

// The first build that reads a removal of the root's person naming the root's log as taking them out (rules/AGENTS.md,
// the lead's, 2026-11-14: after a move the root's person is a member like any other, `~root`). A core of a release
// before it reads such a removal as nothing, so it would make another state: it is told to update (mesh/serve.ts
// `movedTooOld`) only in a workspace whose state in force has the root's person out of `~root` (`Cloud.rootOut`), and
// nowhere else is anyone told anything. 9244: the build of the commit that brought it (#6319,
// d77786f19a). (It was 9285 for that commit alone, a margin over main as the change was made ready: until main reached
// it every core, those that read the rule too, would have been told to update in such a workspace with no release to
// update to. As MOVED_FROM_BUILD above: only ever the build every reader needs, known once the commit is on main.)
export const ROOT_OUT_FROM_BUILD = 9244;
