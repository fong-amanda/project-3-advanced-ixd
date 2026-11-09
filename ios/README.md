# Shared Space for iOS

Native SwiftUI rebuild of `public/sharedSpaceAmanda.html`. iOS 18+, iPhone, built primarily for LiDAR iPhones.

## Folder layout

```
ios/
  project.yml              XcodeGen spec (source of truth for the Xcode project)
  SharedSpace.xcodeproj    generated; regenerate with `xcodegen generate` after adding files outside Xcode
  supabase/schema.sql      tables, security rules, realtime, storage. Run once in Supabase.
  SharedSpace/
    App/                   app entry, navigation (Router, RootView)
    Shared/Models/         SwiftData models (Room, Item, Design, DesignPlacement), enums, Sort rules
    Shared/Sync/           Supabase client, DTOs, SyncEngine (local-first writes + Realtime)
    Shared/Storage/        on-disk files (scans, photos), device capability checks
    Shared/UI/             colours, type, shared components
    Rooms/                 home, room hub, new/join/settings sheets
    Scanning/              RoomPlan capture and review           (stage 2)
    Sort/                  list + one-at-a-time cards            (stage 3)
    Redesign/              dollhouse 3D, catalogue, live AR      (stage 4–5)
    Resources/             assets, Supabase.plist, catalogue + USDZ models
```

## One-time setup

1. **Install Xcode 16 or later** from the App Store, open it once and let it install the iOS components.
2. **Supabase**
   1. Create a project at supabase.com.
   2. Authentication → Sign In / Providers → turn on **Allow anonymous sign-ins**.
   3. SQL Editor → New query → paste all of `supabase/schema.sql` → Run.
   4. Project Settings → API: copy the Project URL and the `anon` public key into
      `SharedSpace/Resources/Supabase.plist`. (Until you do, the app runs on one phone only.)
3. **Open the project**: double-click `SharedSpace.xcodeproj`. Xcode downloads the supabase-swift package on first open.
4. **Signing**: select the SharedSpace target → Signing & Capabilities → choose your Team, and change the
   Bundle Identifier from `com.example.sharedspace` to something unique, e.g. `edu.northeastern.yourname.sharedspace`.
   To make the change permanent, also edit `PRODUCT_BUNDLE_IDENTIFIER` and `DEVELOPMENT_TEAM` in `project.yml`.

## Running on your iPhone

Scanning (RoomPlan) and the live AR view **only run on a real LiDAR iPhone**. The Simulator can run the home
screen, rooms, Sort and the 3D dollhouse, but shows "can’t scan" for everything camera-based.

1. Connect the iPhone 16 Pro with a cable (first time) and tap **Trust** on the phone.
2. On the phone: Settings → Privacy & Security → **Developer Mode** → on (it restarts).
3. In Xcode’s toolbar pick your iPhone as the run destination, then press ⌘R.
4. First run only: on the phone go to Settings → General → VPN & Device Management → trust your developer certificate.

To test two people at once: run on your iPhone as the host, and join as the guest from the Simulator
(or a second phone) using the room code.

## Placeholders to fill before TestFlight

| What | Where |
|---|---|
| Bundle identifier | `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` (or Xcode target settings) |
| Signing team | `DEVELOPMENT_TEAM` in `project.yml` (or Signing & Capabilities) |
| Display name | `INFOPLIST_KEY_CFBundleDisplayName` in `project.yml` |
| Version / build | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`; bump the build for every upload |
| App icon | replace `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (1024×1024, no transparency) |
| Privacy strings | camera text is set in `project.yml` (`INFOPLIST_KEY_NSCameraUsageDescription`) |
