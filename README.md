# Lockeye

A private vault for Android that catches whoever guesses wrong.

Type a wrong PIN and the front camera quietly takes a photo. Everything stays on your phone: no accounts, no ads, no tracking.

## Features

- **Two PINs, two spaces.** Your PIN opens your vault (and can look into the Family space). The family PIN opens only the Family space, never your vault, the intruder photos or the settings.
- **Photo on every wrong PIN.** Anyone who guesses wrong gets photographed, family included. You can turn this off in Settings.
- **Phone lock screen (optional).** Also photographs wrong PIN, pattern or password attempts on the phone's own lock screen. Set it up in Settings → Phone lock screen. Fingerprint and face failures are not reported by Android.
- **Intruder log.** Time, attempt number and photo for each wrong try, newest first.
- **Vault.** Photos, files and notes, kept in the app's private folder.
- **Lockout.** After 5 wrong tries in a row the keypad waits 30 seconds, then longer.
- **Auto lock.** Locks as soon as you leave the app.
- **Light and dark theme.** Follows your phone or set it yourself.
- **In-app updates.** Settings → Updates downloads and installs the newest APK from GitHub. Your data stays.

## Install

Download the latest `Lockeye-vX.Y.Z.apk` from [Releases](../../releases) and install it.

## Build

```
flutter pub get
dart run flutter_launcher_icons
flutter analyze
flutter test
flutter build apk --release
```

Releases are built by GitHub Actions when a tag like `v1.0.0` is pushed.

## Privacy

See [PRIVACY.md](PRIVACY.md).

## License

MIT
