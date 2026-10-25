# mbui iOS CI and manual TestFlight

## What runs

- Existing `mbui.yml` keeps its unrelated Android/macOS/Windows deployment behavior. On each matching main push (or manual dispatch), iOS builds independently of Android's feed. Branch pushes still skip the two macOS jobs to preserve the runner budget. The iOS job has no signing/release environment and uploads `mbui-ios-unsigned-<sha>` for 14 days. Its IPA is **unsigned, not installable as a TestFlight/device distribution**, and is not uploaded to Apple.
- Existing `mbui-check.yml`/pipeline native checks remain unchanged.
- `mbui-testflight.yml` is **workflow_dispatch only**. It requires the full main SHA captured by the manual dispatch, runs the reusable native checks, then enters the `ios-testflight` environment (waiting for approval only if reviewers are configured). Every checkout, test, build and upload stays pinned to that SHA. Main may advance during the run; before building and immediately before upload, the guard fetches main and requires the approved SHA to remain its ancestor. A rolled-back or replaced history that removes the approved commit fails. The input SHA must still equal GitHub's dispatch SHA, so an arbitrary older commit cannot be selected.
- Marketing version defaults explicitly to **0.1.0**. Build number has no default; enter a fresh positive integer. Never derive the marketing version from git history. Both app and share extension get the same explicit version/build. The debug default stays `fail.still.mbui.debug`.

## Existing app, not a new release identity

The release is fixed to ASC app **6818750243**, bundle **fail.still.iphone**, team **D9AAN3VJK8**, and existing group **group.fail.still.iphone**. The old local corrected build-4 archive's public signed entitlements confirm this team/bundle/group. No new app decision is needed just to use this identity. Do not upload the debug bundle to this record or create a new identity as a workaround.

The mbui builder produces Objective-C/MoonBit executables directly, not an Xcode project. It includes `hermes.framework` and `PlugIns/Share.appex`. The new share extension is **fail.still.iphone.share**: it needs its own registered App ID, group association and App Store distribution profile. **Do not reuse the old widget profile** (`StillFailWidgets.appex`). These registrations/profiles may or may not exist externally; this change neither creates them nor claims to have inspected their current availability. Missing/incompatible profiles block the release, not the unsigned build.

Before approving this replacement, review data/login/keychain continuity and removal of the old widget: matching bundle/team/group is necessary, not proof that a rewritten app migrates all old data correctly. Old app entitlements included Sign in with Apple; this native build requests only its currently used group and distribution entitlements. Review native login behavior before release. No app-group migration or silent group change is performed.

**Encryption compliance is a separate release review requirement.** The current source Info.plist already declares `ITSAppUsesNonExemptEncryption=false`; this change does not alter it. Previous ASC handling reportedly selected non-exempt standard/third-party encryption. Resolve that discrepancy with the owner against the actual shipped code and Apple's requirements before enabling release. The workflow does not answer export-compliance questions or submit external beta review.

## Secure GitHub configuration

Protect environment `ios-testflight` with a main-only deployment branch rule (no tags). For a second-person approval policy, also configure required reviewer(s), prevent self-review, and restrict bypass where supported. YAML does not provision these protections; the verified configuration is recorded below. Review the SHA, build, version and source before releasing. Use disposable GitHub-hosted `xcode-27`, never an AirBuild/local keychain or self-hosted signing runner.

Configuration verified on 2026-10-24: `ios-testflight` exists with a custom deployment rule allowing only the `main` branch, the three variables below, and all eight secrets below. `IOS_RELEASE_REVIEWED` is **false**. Required reviewers and prevention of self-review have **not** been configured; the owner has not selected a reviewer. Consequently the environment currently provides no second-person approval. The workflow's manual trigger and release-review variable remain in effect. Decide the approval policy before the first release.

Environment variables:

| Variable | Required value |
| --- | --- |
| `IOS_TEAM_ID` | `D9AAN3VJK8` |
| `IOS_APP_GROUP` | `group.fail.still.iphone` |
| `IOS_RELEASE_REVIEWED` | `true` only after the migration/capability/encryption review above |

Environment secrets (names are placeholders, no values committed):

| Secret | Meaning |
| --- | --- |
| `IOS_DISTRIBUTION_P12_B64` | Base64 Apple Distribution certificate **and private key**, exported explicitly by the owner for CI |
| `IOS_DISTRIBUTION_P12_PASSWORD` | Nonempty P12 password |
| `IOS_SIGNING_SHA1` | Exact 40-hex certificate fingerprint, authorized by both profiles |
| `IOS_APP_PROFILE_B64` | Base64 unexpired App Store profile for `fail.still.iphone`, team/group above |
| `IOS_SHARE_PROFILE_B64` | Separate App Store profile for `fail.still.iphone.share`, same team/group |
| `ASC_KEY_ID` / `ASC_ISSUER_ID` | App Store Connect **team API key** ID / issuer with access to this app and upload permission |
| `ASC_PRIVATE_KEY_B64` | Base64 P8 for that team API key |

No AirBuild-managed credentials are exported or assumed available on GitHub. The CI credentials were created separately: an App Manager team API key, a new Apple Distribution certificate, and new App Store profiles for the app and share extension. Both profiles were checked for the exact team, bundle ID, group, distribution type, expiration and new signing certificate; the encrypted P12 was checked against its private key. The certificate and both profiles expire on 2027-10-24. Secret names were verified in GitHub; their values cannot be read back. Real runner building, signing, code-signature verification, Apple validation and uploading passed on 2026-10-24 for **0.1.0 (9)**. Apple independently reported processing state **VALID** (not expired). The verified source is `ea53c4138ec96a532693c678ec70caaa112687d7`; [Actions run 40104619009](https://github.com/AFK-surf/still.fail/actions/runs/40104619009) contains the upload completion receipt. Tester-group assignment and external beta review are separate. Distribution profiles must be explicit (no wildcard), non-development/non-ad-hoc/non-enterprise, unexpired, and authorize the configured certificate and group. The keychain is temporary, restricted to signing tools, and removed on exit plus an `always()` cleanup step. No signing credentials or signed IPA are uploaded as workflow artifacts. Reference: [GitHub: installing an Apple certificate on macOS runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).

## Release behavior and limitations

`testflight.sh` uses installed macOS `security`, `codesign`, `plutil`, OpenSSL, jq, curl, and Xcode's **`xcrun altool --validate-app/--upload-app`** with the API P8. It does not require an AirBuild `asc` command or invent an Xcode archive/export recipe. The workflow uses the same `xcode-27` runner and `/Applications/Xcode_27.1.app/Contents/Developer` as main’s unsigned iOS build, requiring iPhoneOS SDK **27.1+**, or fails if that toolchain is unavailable or the SDK is too old ([Apple upload requirements](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)). It reads that toolchain's altool help to choose modern kebab-case API authentication flags or the legacy camel-case syntax, without trial uploads. Local Xcode 27 help confirms the modern syntax and `API_PRIVATE_KEYS_DIR`; this is a help-only check, not an Apple request. The supervised 0.1.0 (9) run returned **VERIFY SUCCEEDED** and **UPLOAD SUCCEEDED**, and Apple processing completed as **VALID**. `IOS_RELEASE_REVIEWED` was restored to false afterward. The direct device builder stamps actual SDK/Xcode build metadata, and the share extension declares its arm64 capability; these resolved the initial Apple validation errors. Future failures must still be investigated.

Read-only ASC checks validate the exact app ID/bundle and reject any existing build with the entered number (across marketing versions, including expired builds), before build and again before upload. Failures or incomplete responses abort. The workflow serializes this app's releases, but external/manual uploaders must coordinate: an ASC query cannot reserve a number, and newly uploaded processing builds can have a visibility delay. Apple's duplicate-build rejection is the final guard; there is no overwrite, delete, expire, retry-upload or automatic renumbering. The guard rejects every `GITHUB_RUN_ATTEMPT` except `1`, including reruns of failed jobs, because an ambiguous upload may not yet be visible in ASC. After any interrupted/ambiguous upload, inspect Apple first, then use a new manual dispatch with a fresh build number; do not rerun or reuse that number. Build 4 is already used; do not assume 5 is free.

The app/share profiles are embedded; Hermes is signed first, then the share extension and parent, and code signatures are verified before IPA packaging. Unknown extension/framework counts fail closed. Apple validation must pass before upload. Upload success means only **upload accepted**, not successful processing or tester availability. No group assignment, external beta review, App Store submission or production feed mutation occurs. Existing ASC automatic internal tester settings may still distribute a processed upload according to Apple's configuration.

## Offline validation

Run without credentials/network/builds:

```sh
bash -n apps/mbui/scripts/testflight{,-guard,-asc,-guard-test}.sh
bash apps/mbui/scripts/testflight-guard-test.sh
bash apps/mbui/scripts/testflight-sign-test.sh
```

Also lint both workflow YAML files with the repository's available workflow validator. The manual workflow runs the input guards, offline signing/cleanup contracts and the existing reusable native suite before any release. The guard tests use a real shallow checkout and local Git remote to cover main advancing, checkout drift, rollback and unrelated history. The signing contracts cover macOS Bash 3.2, target order, entitlements, and early/nounset exits. A run succeeds only after the upload script writes its completion receipt; an EXIT cleanup cannot turn a premature exit into a successful upload. These offline checks do not establish real signing, profile compatibility, Apple API availability or upload acceptance.
