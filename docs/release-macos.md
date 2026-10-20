# Signed macOS build

`scripts/export_macos.sh` turns the project into `SECHA.app`, signed with a Developer ID, notarized by Apple and stapled, then zips it as `builds/macos/SECHA-<version>-macos.zip` (`builds/` is git-ignored). Another Mac opens that zip's app without the "unidentified developer" block, and Steam's macOS rule (64-bit, notarized) is met.

```sh
scripts/export_macos.sh            # or: scripts/export_macos.sh /absolute/output/folder
```

The `macOS` preset in `export_presets.cfg` builds a universal (Apple Silicon + Intel) app, `com.cherninlab.secha`, version `application/short_version`. Godot signs every binary with Xcode `codesign` (hardened runtime and secure timestamp come with a real identity). Entitlements stay off: the game needs no JIT and is not sandboxed. GodotSteam will need `codesign/entitlements/disable_library_validation` (and, per its docs, `allow_dyld_environment_variables`) so the Steam library and overlay load in a signed build.

## One-time setup on the signing Mac

Nothing secret is in the repository; the script only names a keychain identity and a keychain profile.

1. Godot 4.7.2 at `/Applications/Godot.app` (or `GODOT=...`) with its 4.7.2 export templates (Editor → Manage Export Templates).
2. An Apple Developer Program membership and a **Developer ID Application** certificate in the login keychain; the preset names it as `Developer ID Application: Fedor Chernin (P9534VH9TZ)`. Back up the certificate with its private key as a password-protected `.p12`, kept out of the repository.
3. A notarytool profile holding an app-specific password: `xcrun notarytool store-credentials SECHA-notary --team-id P9534VH9TZ` (the password is typed at its prompt). Check it with `xcrun notarytool history --keychain-profile SECHA-notary`. `NOTARY_PROFILE` selects another profile.

macOS asks once whether `codesign` may use the signing key; choose Always Allow. Notarization uploads the app to Apple and usually takes a few minutes.

## What the script checks

`codesign --verify --deep --strict` on the export, notarization status `Accepted` (otherwise it prints Apple's log and stops), `stapler validate`, and `spctl --assess`, which must report `source=Notarized Developer ID` — the same Gatekeeper decision a friend's Mac makes. A build signed by someone else's identity needs their own preset change; the Developer ID is personal to its account holder.
