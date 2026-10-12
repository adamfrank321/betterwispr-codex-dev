# Device IPA for external signing

This is an unsigned arm64 iPhone/iPad build, not a simulator build or an App Store release. No Apple certificates, profiles or credentials are included. Signulous compatibility and installation remain unverified until tested on a registered device.

## Download and install

1. Open the repository's Actions tab and select **Device IPA for external signing**.
2. Open the successful run for the desired commit. Under Artifacts, download **BetterWispr-device-unsigned** while signed into GitHub.
3. Extract the downloaded ZIP. Upload **BetterWispr-unsigned.ipa**, not the outer ZIP, to the signing service's custom IPA upload.
4. Preserve the embedded BetterWisprKeyboard extension. Before signing, confirm the service supports the shared App Group requirement below. A generic claim to support entitlements does not establish this.
5. Sign and install using the service's instructions for the registered iPhone. Do not delete an existing installation containing valuable recordings/history without exporting first.
6. Launch BetterWispr, grant microphone and Speech permissions, record a short sentence, edit it and verify it survives relaunch.
7. In iPhone Settings > General > Keyboard > Keyboards, add BetterWispr and enable Full Access. In Notes, select it using the globe menu and insert the saved transcript. The keyboard itself does not record.
8. Report installation errors or missing keyboard transcripts verbatim. Installation alone does not verify shared-container access or desktop sync.

## Required signing configuration

| Bundle | Identifier |
| --- | --- |
| App | `com.adamfrank.betterwispr` |
| Keyboard | `com.adamfrank.betterwispr.keyboard` |

Both require `com.apple.security.application-groups` containing `group.com.adamfrank.betterwispr`, authorized by their provisioning profiles under the signing team. Both Info.plists read that same group from `BetterWisprAppGroup`.

If the signing team must use another group identifier, it must provision that group for both targets AND replace `BetterWisprAppGroup` in both bundled Info.plists. Changing only entitlements will break transcript sharing. Stripping the extension or App Group does not produce a complete test build.

The artifact includes required-entitlements plists for reference, plus a build report recording the commit, toolchain, Mach-O platform/architecture and IPA SHA-256. These reference plists are not provisioning profiles and cannot grant capabilities.

Question for Signulous support: Can a custom IPA containing an iOS keyboard extension be signed with a shared App Group provisioned for both the main app and extension? If the group must be renamed, can both BetterWisprAppGroup Info.plist values be updated to match?

No support message has been sent. Public Signulous documentation confirms custom IPA uploads but does not establish this specific configuration: https://www.signulous.com/register and https://www.signulous.com/support.

## Rebuild

On a Mac with the repository's supported Xcode/Swift toolchain and XcodeGen installed:

```sh
python3 scripts/build_device_ipa.py
```

Output goes to `dist/`. The GitHub workflow runs the same script without signing credentials. The iOS 17 deployment target does not require building with an iOS 27 SDK just to test on iOS 27; runtime compatibility still needs device testing.
