# Releasing LedgerDesk updates

LedgerDesk uses Sparkle 2.10.1. The app checks the `appcast.xml` on the `main` branch and verifies update archives using the public key embedded in the app. The matching private key is stored in this Mac's login Keychain under the Sparkle account `ledgerdesk`; never commit it or share it. Back it up securely: losing it prevents existing installations from accepting future updates.

## Build

Download the official [Sparkle 2.10.1 distribution](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1), extract it outside the repository, and run `SPARKLE_DIR=/path/to/sparkle ./build.sh`. The result is `build/LedgerDesk-Mac.zip`. This ad-hoc-signed build is not notarized and macOS may warn when it is opened.

## Publish an update

1. Increase both `CFBundleShortVersionString` and the numeric `CFBundleVersion` in `Info.plist`; the build version must increase with every release. Build and test the app and make a backup of sample accounting data before testing an update.
2. Create a new GitHub release tag such as `v0.8`. Copy the build ZIP into a clean release directory under a versioned name such as `LedgerDesk-0.8.zip`. Upload that ZIP to the release.
3. Generate the signed feed, using the exact tag and archive name that you uploaded. For example:

   ```sh
   /path/to/sparkle/bin/generate_appcast --account ledgerdesk --maximum-deltas 0 \
     --download-url-prefix https://github.com/jaykumargori/ledgerdesk/releases/download/v0.8/ \
     /path/to/release-directory
   ```

   If keeping old updates, copy the current `appcast.xml` into that directory first; leave previously generated entries unchanged. The tool may request Keychain access. Release notes can be included as a same-named `.md` or `.txt` file; use `--embed-release-notes` to embed them.
4. Check that the generated enclosure URL points to the uploaded ZIP and its `sparkle:edSignature` is present. Replace the repository's `appcast.xml` with the generated file and publish it to `main` **after** the release ZIP is available. Test on a separate Mac with the previous updater-enabled build installed.

An update can only be received after an updater-enabled LedgerDesk is installed. Sparkle checks periodically while the app is running; users can also choose **LedgerDesk > Check for Updates**. Existing accounting data lives outside the app bundle, but backups are still important.
