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

Game keys are redeemed from **Redeem key** on the rack. The first redemption
registers this install with the server and stores its token in shared
preferences (`launcher.token`), so unlocked packs and builds show up on later
launches.
