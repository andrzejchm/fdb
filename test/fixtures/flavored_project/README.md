Realistic-but-trimmed Flutter project tree used to exercise
`writeAppIdFromProjectForLaunch` against the kinds of files a flavored
Flutter project actually produces.

Not a buildable Flutter project. Only the files fdb reads for app-id
resolution are present:

- `ios/Runner/Info.plist`
- `ios/Flutter/Debug-staging.xcconfig`
- `ios/Runner.xcodeproj/project.pbxproj`
- `macos/Runner/Info.plist`
- `macos/Runner/Configs/AppInfo.xcconfig`
- `macos/Flutter/Debug-staging.xcconfig`
- `macos/Runner/Configs/Debug-canary.xcconfig`
- `macos/Runner.xcodeproj/project.pbxproj`
- `android/app/build.gradle.kts`

Flavors wired in:

- `staging` resolves via xcconfig on iOS and via the Flutter xcconfig on macOS.
- `prod` resolves via the pbxproj `Debug-prod` build configuration on iOS.
- `canary` resolves via `macos/Runner/Configs/Debug-canary.xcconfig`.
- `internal` resolves via the pbxproj `Debug-internal` build configuration on macOS.
- Android `staging` uses an explicit `applicationId` + flavor `applicationIdSuffix`.
- Android `prod` uses `applicationIdSuffix` only (composed from `defaultConfig.applicationId`).
- Android debug `applicationIdSuffix` is appended on top.
