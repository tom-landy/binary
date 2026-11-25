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

For TestFlight, create the app record in App Store Connect using `com.warhound.binary`. Set up production CloudKit schema in CloudKit Console before distributing, then select a generic iOS device destination in Xcode, choose **Product → Archive**, and use **Distribute App** in Organizer. Provisioning and upload use your own Apple Developer team. The source archive contains no signing credentials.

## Device checks

- Create an instant weekday habit and a timed habit. Toggle the instant habit in the app and in its Home Screen or Lock Screen widget. Check the history dots and today’s count.
- Give the timed habit a one-minute Work interval. Pause and resume in the app and in the Live Activity. Let Work finish, reopen Binary if it was suspended, and verify the timed habit logs on the Work deadline’s date. Test manual completion and skipping independently.
- Enable completion notifications and test a locked-device interval. The countdown uses a persisted deadline. iOS can deliver a local reminder while Binary is suspended. Binary records completion and advances the phase when its active UI next reconciles that deadline. Keep-awake applies while Binary is active.
- Test the timer widget, Siri shortcuts, Action Button shortcut assignment, and the Binary Focus filter. Test the 10 themes and optional Home Screen icon matching.
- Open Binary on an iPad and confirm the two-pane layout at regular width. Toggle an instant habit on the paired Watch and verify the change syncs through iCloud.
