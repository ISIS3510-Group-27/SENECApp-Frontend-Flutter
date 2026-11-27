# Sprint 4 — delivery status

## Built and verified on November 27, 2026

- Real app target: `lib/main.dart`, release mode, Flutter 3.47.4 / Java 17.
- APK: `output/android/isis3510-27-flutter-Sprint4.apk` (59,824,744 bytes).
- SHA-256: `dbc93f10e71a780228682fd5d7970bc0a60848df4f57581a91af09307f7efc4a`.
- Package: `co.edu.uniandes.senecapp`, version `1.0.0` / code `1`, minimum API 24.
- Flutter engine/app ABIs: ARM64 and ARM32. Some plugins also bundle x86_64
  libraries; that does not make this an x86_64 Flutter build.
- API: `https://35-170-175-16.sslip.io/api/v1`, `AUTH_MODE=firebase`, project
  `senecapp`. No diagnostic font assets or integration-test target in this APK.
- Installed successfully on the temporary ARM emulator and opened the university
  sign-in screen. See [startup capture](evidence/release-startup.png) and
  [build metadata](evidence/release-build.json). No real sign-in was performed.
- Full Flutter suite: 338 passed. Static analysis: no issues. Controlled native
  SQLite/offline/reconnect/attribution session passed.

The APK and detailed build/signature logs are deliberately ignored by Git.
The APK uses the project's existing **Android Debug certificate** configuration.
It is an internal/course artifact, not a production-signed release. Review the
team's signing/Firebase setup before distributing it. Real Microsoft/Firebase
authentication, including provider certificate requirements, is not verified by
opening the sign-in screen. The AOSP test image has no Google Play services.

The optimized filter and supporting source files are still uncommitted on
`feature/Jose`. The APK combines base revision `20ac47f` with that filter change.
`output/android/build-metadata.json`, `apk-signature.txt` and
`resolved-pubspec.lock.txt` preserve build provenance. The repository lockfile,
Firebase settings and shared Android SDK paths were not changed for this build.

## Build again

With Android SDK installed and Java 17 selected:

```sh
flutter build apk --release --target=lib/main.dart \
  --target-platform=android-arm,android-arm64 \
  --dart-define=API_BASE_URL=https://35-170-175-16.sslip.io/api/v1 \
  --dart-define=AUTH_MODE=firebase
```

Allow Flutter to regenerate its plugin registrant for release. After running an
integration-test target, separately running `pub get` and then using `--no-pub`
left a stale dev-plugin registration in this installed Flutter version; the
normal release command above regenerated it correctly. This required no edit to
the project's Java/Kotlin/Firebase configuration.

The temporary emulator, SDK, system image, isolated Gradle cache and build copy
were removed after exporting the evidence/APK. The cleanup recorded **15.29 GiB**
of allocated files removed; see [cleanup report](evidence/android-cleanup.json).
The installed Flutter and Java were preserved. Reinstall Android tooling before
trying to run Android again; unit/widget tests do not require the emulator.

## Required external steps still pending

1. Repeat the comparison and before/after profiling on a **physical Android**.
   Emulator evidence does not fulfill the course's physical-device requirement.
2. Validate authenticated BQ6 collection/dashboard changes with an authorized,
   verified test account. Controlled fixture requests are not production joins.
3. Record the student's visible ethics reflection and add the final team video
   link. [Preparation prompts](ETHICS_NOTES.md) are not a recorded contribution.
4. Review/sign the build as agreed by the team, upload it to the correct Firebase
   App Distribution app, add the authorized testers and verify acceptance/install.
   No release upload or invitations were sent during this work.
5. Complete the course's team notification after distribution. No message was
   sent on the student's behalf.
6. Review and commit the source work, preferably separating generated-file
   cleanup from the filter optimization/tests/evidence. Nothing is staged.

For distribution release notes, accurately describe the comparison, read-only
offline snapshot and measured filter optimization; include the production
validation limitations above. Do not describe synthetic data as real adoption.
