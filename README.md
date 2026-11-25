# Binary

Binary is Warhound’s habit tracker and Work/Rest focus timer for iPhone, iPad, and Apple Watch.

## Generate and open the project

Use macOS with Xcode 16 or later and the iOS and watchOS platforms installed in Xcode Settings. Open Terminal in the extracted `Binary` folder. If you use Homebrew, install [XcodeGen](https://github.com/yonaskolb/XcodeGen) with `brew install xcodegen`. Then run:

```sh
xcodegen generate
open Binary.xcodeproj
```

For a first build, select the **Binary** scheme and an iOS 18+ iPhone simulator, then choose **Product → Run**. You can also build without signing from Terminal:

```sh
xcodebuild -project Binary.xcodeproj -scheme Binary \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Run on your iPhone

1. Add your Apple Developer account in **Xcode → Settings → Accounts**. Use an Apple Developer Program team that can provision the capabilities below.
2. In **Signing & Capabilities**, enable **Automatically manage signing** and choose the same team for all three targets. Create or select these identifiers and capability assignments in your Apple Developer account.

   | Target | Bundle identifier | Capability assignments |
   | --- | --- | --- |
   | Binary | `com.warhound.binary` | App Group `group.com.warhound.binary`, CloudKit `iCloud.com.warhound.binary`, Push Notifications |
   | BinaryWidgets | `com.warhound.binary.widgets` | App Group `group.com.warhound.binary` |
   | BinaryWatch | `com.warhound.binary.watchkitapp` | CloudKit `iCloud.com.warhound.binary`, Push Notifications |

3. Connect and trust your iPhone, enable **Developer Mode** if prompted, and select the phone as the destination for the **Binary** scheme. Choose **Product → Run**.
4. For iCloud and Watch testing, sign into the same iCloud account on the devices. If SwiftData cannot open its CloudKit-backed configuration on iPhone or iPad, Binary tries opening the shared store locally and shows its local status in Settings.

## TestFlight

Already set in the project: version 1.0 (build 1), privacy manifests for the app and widget extension, the encryption declaration (`ITSAppUsesNonExemptEncryption` = NO, so uploads skip the export compliance question), all four iPad orientations, the app category, and a launch background that matches light and dark mode. Every push to `main` and every pull request is compiled by the GitHub Actions workflow in `.github/workflows/build.yml`.

One-time setup, in this order:

1. In the Apple Developer portal, register the three bundle identifiers, the App Group and the iCloud container listed in the table above.
2. In App Store Connect, create the app record with bundle identifier `com.warhound.binary`.
3. Run Binary once from Xcode on a device signed into iCloud, create a habit, then open CloudKit Console, select `iCloud.com.warhound.binary` and choose **Deploy Schema Changes** to production. TestFlight builds use the production CloudKit environment, so sync fails until this is done.

For each build:

1. Increase `CURRENT_PROJECT_VERSION` in `project.yml` (App Store Connect rejects a repeated build number), then run `xcodegen generate`.
2. Select **Any iOS Device (arm64)** as the destination and choose **Product → Archive**.
3. In Organizer, choose **Distribute App → TestFlight & App Store**. Xcode switches the push entitlement to production when it signs for distribution.
4. When processing finishes in App Store Connect, add the build to an internal testing group. External testers also need a short beta description and Beta App Review.

## Device checks

- Create an instant weekday habit and a timed habit. Toggle the instant habit in the app and in its Home Screen or Lock Screen widget. Check the tile’s week dots, the progress ring and the streak chip. Tap the 0/1 circle on the timed habit to mark it done by hand, and hold a tile to edit.
- Start a session, then tap a different timed habit, a preset, or Reset. Binary should ask before replacing the session.
- Give the timed habit a one-minute Work interval. Pause and resume in the app and in the Live Activity. Let Work finish, reopen Binary if it was suspended, and verify the timed habit logs on the Work deadline’s date. Test manual completion and skipping independently.
- Enable completion notifications and test a locked-device interval. The countdown uses a persisted deadline. iOS can deliver a local reminder while Binary is suspended. Binary records completion and advances the phase when its active UI next reconciles that deadline. Keep-awake applies while Binary is active.
- Add the medium Today widget and toggle a habit from it.
- Test the timer widget: it should show the live countdown, and its button should pause and resume. Let a habit-linked Work interval finish with Binary closed, then press play on the widget. The habit should be logged and Rest should start. Check the Live Activity reads “Work complete” once the interval has ended.
- Test Siri shortcuts, Action Button shortcut assignment, and the Binary Focus filter. Test light and dark appearance, and the 10 accents in the app, widgets and Live Activity, and Home Screen icon matching. Violet is the primary icon.
- Open Binary on an iPad and confirm the two-pane layout at regular width. Toggle an instant habit on the paired Watch and verify the change syncs through iCloud.
