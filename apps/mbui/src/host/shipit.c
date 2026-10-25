// The last step of still.fail's desktop app's updater (Electron's: Squirrel.Mac's ShipIt), which runs out of the app it
// has just put in place: with the bundles swapped, it opens the new one by running the new bundle's
// Contents/Frameworks/Squirrel.framework/Resources/ShipIt <launch request> <the app's path>, a ShipIt of the new app's
// own. Built in that app's place (scripts/mac-app.sh's stable and beta variants), this app carries this there, so the
// Electron app's last update opens it as each of its own updates opened the next: the app's path opened as the
// Finder opens it (LaunchServices, which gives the app its LSEnvironment).
#include <unistd.h>

int main(int argc, char **argv) {
  if (argc < 3) return 1;
  execl("/usr/bin/open", "open", argv[2], (char *)0);
  return 1;
}
