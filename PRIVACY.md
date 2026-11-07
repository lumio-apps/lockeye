# Privacy Policy

**App:** Lockeye (package `com.lumioapps.lockeye`)
**Developer:** Lumio Apps
**Last updated:** November 6, 2026

Lockeye is built to respect your privacy.

## Data we collect

**None.** Lockeye does not collect, transmit or share any personal or usage data.

- No accounts or sign-in
- No ads
- No analytics, crash reporting or tracking
- No third-party services that collect data

## Data stored on your device

- Your PINs are never stored. They only unlock the encryption keys of the vault (see below)
- Your settings
- The intruder log and the photos taken after wrong PIN attempts
- The photos, files and notes you add to the vault, encrypted

All of it stays in the app's private storage on your phone. Other apps and the gallery cannot see it. Uninstalling the app removes all of it.

## Encryption

Photos, files, notes and their file names in the vault are encrypted on the phone with AES-256-GCM. Each space has its own random key. The keys are protected by your PINs (PBKDF2, 150 000 rounds) and by a key held in the Android Keystore of this phone, so a copy of the app's files cannot be opened on another device. While the app is open, decrypted data is kept only in memory. Opening a file in another app makes a temporary plain copy, which is deleted the next time Lockeye starts or unlocks.

The intruder photos and the intruder log are not encrypted.

If you forget your PIN, the vault cannot be recovered. There is no reset.

## Screenshots

Screenshots, screen recording and the preview in Recent apps are blocked by default. Turn this off in Settings → Privacy.

## Camera

Lockeye uses the front camera only to take a photo when a wrong PIN is entered. The photo is saved on your phone and is never uploaded. You can turn this off in Settings → Photo on wrong PIN.

## Phone lock screen (optional)

If you turn on **Settings → Phone lock screen**, Lockeye also takes a front camera photo when someone enters a wrong PIN, pattern or password on the phone's own lock screen. This is off until you set it up.

- It uses Android's **device admin** feature with only the "watch login attempts" policy. Android tells Lockeye that an attempt failed. Lockeye cannot see, read or change your phone's PIN, and cannot lock or wipe the phone.
- While taking the photo, Lockeye shows a small notification and a 1 pixel invisible window. Android requires this for camera use from the background.
- Photos and log entries are kept in the app's private storage, exactly like the in-app ones. Nothing is uploaded.
- Turn it off in the same screen. This also removes the device admin access, which is needed before you can uninstall the app.

## Internet access

Lockeye works completely offline. The optional **Updates** button asks the public GitHub API whether a newer version exists and, if you agree, downloads it from GitHub. No personal data is sent. GitHub's own privacy statement applies to that request: https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement

## Permissions

| Permission | Why |
| --- | --- |
| Camera | Take a photo after a wrong PIN |
| Internet | Check for updates when you tap the button |
| Install packages | Install a downloaded update after you confirm |
| Device admin (optional) | Learn that a phone lock screen attempt failed. Only the "watch login attempts" policy |
| Display over other apps (optional) | Lets the camera run on the lock screen |
| Foreground service, camera (optional) | Runs the camera for a few seconds after a failed lock screen attempt |
| Notifications (optional) | Shows the small notice Android requires while the camera runs |

## Children

Lockeye does not collect data from anyone, including children.

## Changes

If this policy changes, the new version will be published in this repository.

## Contact

Open an issue in this repository.
