# lib_boloto_launcher

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Modpack catalog

The rack is loaded from the website's launcher API (`/api/launcher/`, see
`LAUNCHER_API.md` in the website repo). It defaults to `https://boloto.studio`;
point it at a local Django server with:

```bash
flutter run -d windows --dart-define=BOLOTO_API=http://127.0.0.1:8000
```

Game keys are redeemed in **Settings › 03 · Keys**, which also lists what this
launcher has unlocked and has **Rescan** to reload the rack. The first redemption
registers this install with the server and stores its token in shared
preferences (`launcher.token`), so unlocked packs and builds show up on later
launches.

## Accounts

The account button in the header signs in with a boloto.studio website
account (the same username and password as frogs.net). Keys redeemed while
signed in belong to the account, so the unlocks show up on any PC the user
signs in on. Keys redeemed before signing in move into the account.

## Playing: Minecraft sign-in, install and launch

**Run** on a pack build does everything itself (no official launcher, no
Forge installer window), streaming progress and the game's output to the
deck's log:

1. **Minecraft account**: Microsoft sign-in with a code you enter at
   microsoft.com/link (Settings › Launcher › Minecraft, or prompted on Run).
   Tokens are kept in the OS credential store and refreshed automatically.
2. **Java**: Mojang's own runtime for that Minecraft version (Java 17 for
   1.20.1), under `~/.boloto/runtime`.
3. **Minecraft**: client jar, libraries, natives and assets from Mojang,
   under `~/.boloto/{versions,libraries,assets}` (shared by all packs).
4. **Forge**: the build's Forge version; its installer's processors are run
   headlessly with the downloaded Java.
5. **Pack files**: the build's git repo/branch is synced into
   `~/.boloto/instances/<build-slug>` (shallow fetch, reset to the branch,
   `git lfs pull`). `options.default.txt` / `servers.default.dat` are copied
   to `options.txt` / `servers.dat` only on first install. Uses system git
   if it has git-lfs; on Windows otherwise downloads a pinned MinGit +
   Git LFS into `~/.boloto/tools`.
6. **Launch**: `java …` with the merged vanilla + Forge arguments, in the
   instance folder.

Each build on the website needs **Minecraft version**, **mod loader**
(`forge`) and **loader version** set, plus the git URL and branch.

### One-time setup: Azure app for Microsoft sign-in

1. In the Azure portal → App registrations → New registration:
   - Supported account types: **Personal Microsoft accounts only**.
   - No redirect URI needed.
   - Authentication → **Allow public client flows: Yes** (device code).
2. Copy the **Application (client) ID**.
3. Ask Mojang to allow it to use the Minecraft API:
   <https://aka.ms/mce-reviewappid>. Until it's approved, sign-in stops at
   the last step with "Minecraft refused this launcher's app registration".
4. Build/run with the ID:

```bash
flutter run -d windows --dart-define=BOLOTO_MS_CLIENT_ID=<client-id>
```

Debug builds also offer an **offline profile** in the sign-in dialog, so the
whole download + Forge + launch pipeline can be tested before Mojang
approves the app (singleplayer only; release builds don't have it).

If the Windows build fails with `atlstr.h` missing (flutter_secure_storage),
add the **C++ ATL for latest build tools** component in the Visual Studio
Installer.
