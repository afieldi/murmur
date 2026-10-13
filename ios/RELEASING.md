# Releasing murmur for iPhone

How a build gets from this repo to TestFlight (ios/prd.json IOS-015). Desktop has its own runbook in the root RELEASING.md. The order matters; each step assumes the previous one held.

## Version and build numbers

- **Version** is `MARKETING_VERSION` in `ios/project.yml` (0.1.0 for the TestFlight builds). Bump it in its own commit when an App Store version changes.
- **Build** is the number of commits behind the build (`git rev-list --count HEAD`). `npm run ios:release` sets it at archive time, so `CURRENT_PROJECT_VERSION` in `ios/project.yml` stays 1 and is never edited by hand. It only grows, so every new commit uploads with a new build number. App Store Connect refuses a second upload of the same build number, so a rebuild of the same commit needs a new commit first.

## What the Mac needs once

- The App Store Connect API key in the environment: `APPLE_API_KEY` (the path to the .p8 file), `APPLE_API_KEY_ID`, and `APPLE_API_ISSUER`. On LaBroi's Mac they live in `~/.config/apple-notary/env`, which `~/.zshenv` loads. Never print them, log them, or commit them.
- The Apple Distribution certificate for Eze Media LLC (team 4B55ZVBVKN) in the login keychain.
- The App Store Connect record murmur voice dictation for `com.lbwalton.murmur.ios`, which exists (IOS-004).

Signing uses the API key with automatic provisioning: the first archive creates the App Store profiles for the app and the keyboard. `--xcode-account` signs with the account signed in to Xcode instead, which works only from a Terminal that can read the login keychain.

## Archive, check, and upload

1. **Gates.** `npm run typecheck`, `npm run test`, `npm run ios:test`, and `npm run ios:smoke` green on the commit you ship.
2. **Dry run.** `npm run ios:release -- --no-upload` generates the project, archives murmur for the App Store, exports the signed ipa into `ios/build/release/<version>-<build>/export/`, and checks it. Nothing is sent. The checks:
   - the version and build number in the archive;
   - export compliance set (below);
   - the keyboard carrying the same build;
   - both bundles in the ipa signed for the App Store, with no test devices and profiles that carry the app group.
3. **Upload.** `npm run ios:release` does all of that, then has Apple validate the ipa, then uploads it. Ask LaBroi before every upload: it sends the build to Apple.
4. **Processing.** App Store Connect processes the build for 5 to 30 minutes. Apple emails lbwalton@gmail.com when it is ready, or when it is not and why.

## Export compliance

murmur makes only HTTPS requests through Apple's own networking and adds no encryption of its own, so it is exempt. `ITSAppUsesNonExemptEncryption` is false in the app's Info.plist, and App Store Connect does not ask about encryption for each build. If murmur ever adds encryption of its own, this answer changes before the next upload.

## TestFlight test notes

Paste this into the build's What to Test in App Store Connect, TestFlight, under the build:

> First TestFlight build of murmur voice dictation. Finish first run: microphone, the murmur keyboard, Full Access, and your provider key. Then dictate with the murmur keyboard in Messages, Notes, Mail, and Safari. Try a take where you say nothing (nothing should be typed) and a take with Wi-Fi and cellular off (it should wait, then send when you retry). If something goes wrong, Settings, Diagnostics, Save report makes a report you can read and then share.

## Internal testing

- In App Store Connect, open murmur voice dictation, then TestFlight. Once, create an internal group (murmur internal) with LaBroi in it and automatic distribution on, so every processed build reaches it.
- On the iPhone, install TestFlight from the App Store. The invite goes to lbwalton@gmail.com, the App Store Connect account; the phone's iCloud is a different Apple ID, so open the invite email on the phone, or sign in to TestFlight as lbwalton@gmail.com.

## Before inviting anyone else

- LaBroi's live checks in HANDOFF.md pass on his own iPhone first.
- External testers need Beta App Review: fill in Test Information in App Store Connect (a feedback email, a contact, the privacy policy address, a beta description) and the app's privacy details. murmur collects nothing itself: takes go only to the provider you choose with your own key, and diagnostics are never sent by themselves.
- Problems found in TestFlight become fixes or stories in ios/prd.json before the next build (IOS-015).
