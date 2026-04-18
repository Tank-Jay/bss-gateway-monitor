# BSS Gateway Monitor — Flutter Native Mobile App

Native Android/iOS BLE monitor for the BSS IoT Gateway (ESP32-S3). Built because Chrome Web Bluetooth is unreliable — this uses the platform's native BLE stack via `flutter_blue_plus` and connects every time nRF Connect does.

Matches the firmware exactly: 3 BLE services, 6 characteristics, Pod Summary 1s auto-notify, Reboot/Factory Reset commands.

## Features

- **Login screen** — credentials `Jaytank` / `Jay@2526` (or `admin` / `admin`)
- **Dashboard** — Station Info (WiFi/MQTT/SD/heap/faults) + live Pod Summary (auto-updates every 1s)
- **Pods tab** — Pod selector (1-5), SOC bar, full telemetry, 16 cell voltages (min/max highlighted), 6 NTC + 4 PDU temperatures
- **Log tab** — Full BLE TX/RX log with timestamps
- **Profile tab** — User info, remote control (Reboot/Factory Reset with confirm), about section, sign out

## Build from Source

### 1. Install Flutter SDK

Download from [flutter.dev/docs/get-started/install/windows](https://docs.flutter.dev/get-started/install/windows).

Verify:
```bash
flutter --version
flutter doctor
```

### 2. Build & install on connected phone

From this directory (`mobile_app/`):

```bash
# Install dependencies
flutter pub get

# Connect Android phone via USB with USB Debugging enabled
# Verify phone is detected:
flutter devices

# Build & install in one step
flutter run --release
```

### 3. Or build standalone APK (no PC needed after)

```bash
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

Transfer that APK to any Android phone, tap to install (allow "Install from unknown sources").

## Permissions

The app requests:
- **Bluetooth Scan** (Android 12+)
- **Bluetooth Connect** (Android 12+)
- **Fine Location** (required for BLE scan on Android < 12)

All configured in `android/app/src/main/AndroidManifest.xml`.

## BLE Architecture (must match firmware)

| UUID | Type | Purpose |
|---|---|---|
| `e1ec0001-...` | Service | Info |
| &nbsp;&nbsp;`e1ec0101-...` | READ | Station Info (JSON) |
| `e1ec0002-...` | Service | Pod |
| &nbsp;&nbsp;`e1ec0201-...` | READ + NOTIFY | Pod Summary (auto-push every 1s) |
| &nbsp;&nbsp;`e1ec0202-...` | WRITE | Pod Select (write "1"-"5") |
| &nbsp;&nbsp;`e1ec0203-...` | READ | Pod Detail (JSON for selected pod) |
| `e1ec0003-...` | Service | Control |
| &nbsp;&nbsp;`e1ec0301-...` | WRITE | Command ("reboot" / "factory_reset") |
| &nbsp;&nbsp;`e1ec0302-...` | READ + NOTIFY | Response (JSON result) |

Device name prefix: `BSSX_` (or `BSS_`) — app scans for both.

## Project Structure

```
mobile_app/
├── pubspec.yaml                              # Dependencies
├── android/app/src/main/AndroidManifest.xml  # BLE permissions
├── lib/
│   └── main.dart                             # Complete app (UI + BLE service)
└── README.md                                 # This file
```

## Troubleshooting

**"Bluetooth permissions denied"**
→ On Android 12+: Settings → Apps → BSS Gateway → Permissions → grant Nearby Devices
→ On Android < 12: also grant Location

**"No BSS device found"**
→ Make sure ESP32 is powered and BLE_Init has run (wait 15s after boot)
→ Verify with nRF Connect that `BSSX_IDR001` is advertising

**Gradle build fails**
→ `flutter clean && flutter pub get` then retry
→ Make sure your `ANDROID_HOME` environment variable is set

## Why Not Web App?

Chrome Web Bluetooth on Android has documented reliability issues with ESP32 devices — GATT discovery often times out even when the device is working perfectly (nRF Connect confirmed our firmware works). This native app uses the same BLE stack nRF Connect uses, so it's rock-solid.
