# iOS app to TestFlight

`.github/workflows/mbui-independent-testflight.yml` puts still.fail mbui's iOS app (App Store Connect app `6826455869`,
`fail.still.mbui` with its Share extension `fail.still.mbui.share`, App Group `group.fail.still.mbui`, team
`D9AAN3VJK8`) on TestFlight for the internal group: on main, each push that changes what the app is built from, or by
hand (Actions → mbui independent TestFlight → Run workflow). The original app (`6818750243`, `fail.still.iphone`)
keeps its separate manual `mbui-testflight.yml` workflow and upload lock.

## How it goes

| Job | Runner | What |
| --- | --- | --- |
| `build` | `xcode-27` | `ios-testflight.rb prepare`: checks the credentials, the app and the group in App Store Connect; the build's number is main's commit count (version `0.1.<it>`, as every still.fail app's), and when App Store Connect already has it the run stops there (a rerun never uploads twice). Otherwise the signing identity goes into a keychain of the run's own, the app is built as mbui.yml's `ios` job builds it (its caches, restored only), and `package` archives and exports it for the App Store through a generated Xcode project (`apps/mbui/scripts/ios-package/`) and checks ids, version, team, entitlements and signatures. The `.ipa` and its SHA-256 are the run's artifact. |
| `upload` | `macos-15` | `ios-testflight.rb upload`: the `.ipa` checked against its SHA-256, uploaded with `altool` and the App Store Connect key. |

Apple's processing (often longer than a CI job may take, 10 minutes) is waited for by no job: the internal group has
automatic distribution on, so it takes each build once Apple has processed it. Both jobs remove the keychain, the
profiles and the key whatever happened (`ios-testflight-cleanup.rb`); no credential is in an artifact or a cache.

Checked offline: `ruby apps/mbui/scripts/ios-testflight-test.rb`, `python3 apps/mbui/scripts/ios-package/test-install.py`.

## Setup (once, by whoever holds the Apple account and the repository's settings)

1. GitHub → Settings → Environments → `ios-testflight`, deployment branches: `main` only.
2. Its secrets (each file Base64-encoded whole: `base64 -i FILE | tr -d '\n' | pbcopy`):

   | Secret | Value |
   | --- | --- |
   | `IOS_DISTRIBUTION_P12_B64` | The existing GitHub CI Apple Distribution certificate of team `D9AAN3VJK8` with its private key, as `.p12`; shared with the original app |
   | `IOS_DISTRIBUTION_P12_PASSWORD` | That `.p12`'s existing password |
   | `MBUI_IOS_APP_PROFILE_BASE64` | An App Store distribution profile for `fail.still.mbui`, with `group.fail.still.mbui` and that certificate |
   | `MBUI_IOS_SHARE_PROFILE_BASE64` | The same for `fail.still.mbui.share` |
   | `MBUI_ASC_KEY_ID` | A team App Store Connect API key's Key ID (App Store Connect → Users and Access → Integrations) |
   | `MBUI_ASC_ISSUER_ID` | Its Issuer ID |
   | `MBUI_ASC_PRIVATE_KEY_BASE64` | Its `AuthKey_<Key ID>.p8` |

   The workflow maps the two shared certificate secrets to the script's `MBUI_IOS_CERTIFICATE_*` environment
   variables. Its profiles and App Store Connect API key remain specific to the independent app. Certificate
   renewal must update both apps' profiles; revoking the shared certificate affects both release workflows.

3. Its variable `MBUI_TESTFLIGHT_GROUP_ID`: `2e1bd33b-eda4-4c5a-b764-88c8c701749c`
   (`mbui-ci-internal-non-france`). The group is internal, without a public link, with automatic distribution on.
   It is intentionally empty at the owner's request; add only explicitly authorized testers before an installation
   check. The current beta excludes France. The earlier manual group `5f3be0e4-d831-43e7-8abe-994a95575a70` remains
   empty and is not the CI target. Automatic distribution was selected when creating the new group; the API does
   not accept `hasAccessToAllBuilds` in an update request.
4. Run the workflow by hand once, and install the build from TestFlight.

## Configuration verified on 2026-10-24

- `ios-testflight` allows only `main`; five mbui-specific secrets are present, along with the two shared certificate
  secrets. The API key has the App Manager role.
- App Store profiles `QS6S75YFK4` (app) and `X4Q548S34B` (Share) use certificate `TNH78KLMD6`; both were decoded and
  checked for the exact bundle IDs, team, `group.fail.still.mbui`, distribution entitlements and expiry
  (`2027-10-24T13:29:23Z`). No private signing material is committed.
- The new CI group belongs to app `6826455869`, has automatic distribution enabled, and has zero testers.
- No independent-app GitHub signing/upload run or TestFlight installation has been performed by this setup.
