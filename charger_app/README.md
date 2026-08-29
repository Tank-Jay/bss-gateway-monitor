# BSS Charger Monitor

Android app for BLE monitoring of ESP32-S3 **2-bay battery chargers**.
One charger holds two batteries; a deployment scales to **50 chargers = 100
batteries**, and all of them are visible at once.

Companion firmware: [`src/Charger_BLE_Handler/`](../src/Charger_BLE_Handler/)
Wire protocol: [`doc/Charger_BLE_Protocol.md`](../doc/Charger_BLE_Protocol.md)

---

## Why it is built in two tiers

A phone has one BLE radio and cannot hold 50 GATT connections. So the app never
tries to.

**Tier 1 — Fleet view (no connection).** Every charger broadcasts a 17-byte
manufacturer-data payload once a second: charger ID, state, fault bitmap, and
for each bay its presence, SOC, voltage and temperature. The app runs a
continuous passive scan and decodes those advertisements directly, so all 50
chargers and 100 batteries update live without pairing, connecting, or
round-tripping anything.

**Tier 2 — Charger detail (connected).** Tapping a charger opens a GATT link to
that one unit: per-cell voltages, temperature probes, cycles, SOH, capacity,
and control commands, streamed at 1 Hz.

The fleet scan is paused while a charger session is open. Android will let you
scan and connect simultaneously, but the scan starves the connection of radio
time and the 1 Hz notifications start arriving late.

---

## Screens

| Screen | What it shows |
|--------|---------------|
| **Fleet** | Grid of every charger in range. Per charger: ID, state, signal, and both bays as SOC bars with voltage and temperature. Roll-up strip across the top counts batteries, charging, full, faults and fleet average SOC. Search, sort (ID / SOC / faults / signal) and a faults-only filter. |
| **Charger** | Connected view of one unit: mains voltage, uptime, firmware, Wi-Fi, active faults, and a full panel per bay with start / stop / unlock. |
| **Battery detail** | Per-cell BMS for one pack: SOC, pack V/A, SOH, capacity, cycles, cell-imbalance delta, a live SOC + current trend chart, every cell voltage colour-coded against the pack min/max, and all temperature probes. |
| **BLE log** | Raw TX/RX traffic for the active link, copyable. |
| **Settings** | Theme, fleet counters, CSV export, demo mode, protocol info. |

---

## Demo mode

Settings → **Demo mode** populates a synthetic 50-charger fleet so the UI can be
exercised, demoed and reviewed with no hardware present. It never touches the
radio, uses a fixed random seed so screenshots are reproducible, and shows a
persistent banner so simulated numbers are never mistaken for real ones.
Connecting to a demo charger is blocked — there is nothing to connect to.

---

## Building

```bash
cd charger_app
flutter pub get
flutter analyze
flutter build apk --release
```

`android/` is generated, not checked in. If it is missing, recreate it:

```bash
flutter create --project-name bss_charger_monitor --org com.bss.charger --platforms android .
```

That preserves `pubspec.yaml`, `lib/` and the customized
`android/app/src/main/AndroidManifest.xml`.

CI builds and releases the APK on every push touching `charger_app/`:
[`.github/workflows/build-charger-apk.yml`](../.github/workflows/build-charger-apk.yml).

### Troubleshooting local builds

**`resource mipmap/launcher_icon not found`** — the manifest points at an icon
that `flutter_launcher_icons` generates. Run it before the first build:

```bash
dart run flutter_launcher_icons
```

**`Gradle build daemon disappeared unexpectedly`** — the Flutter template sets
`org.gradle.jvmargs=-Xmx8G` in `android/gradle.properties`. On a machine with
less free RAM than that the daemon is OOM-killed part-way through. Lower it:

```properties
org.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=512m
org.gradle.daemon=false
```

`android/gradle.properties` is generated and git-ignored, so this is a local
workaround only — CI regenerates it and builds with the default settings.

---

## Permissions

| Permission | Why |
|------------|-----|
| `BLUETOOTH_SCAN` (`neverForLocation`) | The fleet view — this is the one that matters |
| `BLUETOOTH_CONNECT` | Only needed once you tap into a charger |
| `ACCESS_FINE_LOCATION` (maxSdk 30) | Android 11 and below refuse to return scan results without it |

There is no `INTERNET` permission. The app talks to chargers over BLE and
nothing else.

---

## Source layout

```
lib/
  main.dart                      app shell, theme wiring
  src/
    ble/
      ble_uuids.dart             GATT UUIDs — mirror of the firmware header
      fleet_scanner.dart         Tier 1: continuous scan, decode, filter, sort, demo
      charger_ble_service.dart   Tier 2: GATT link to one charger
    models/
      charger_adv.dart           advertisement decoder + state enums + fault map
      log_entry.dart             log and chart sample types
    screens/
      fleet_screen.dart          home — all chargers, all batteries
      charger_screen.dart        one connected charger, both bays
      battery_detail_screen.dart per-cell BMS for one pack
      log_screen.dart            raw BLE traffic
      settings_screen.dart       theme, CSV export, demo mode
    theme/palette.dart           light + dark palettes, SOC colour ramp
    widgets/
      common.dart                Panel, MetricTile, SocBar, StatusChip, LiveDot
      charger_tile.dart          one charger in the fleet grid
```

---

## Relationship to the gateway app

[`mobile_app/`](../mobile_app/) is a different product — the 5-pod BSS gateway,
`BSSX_` name prefix, `e1ec00xx` service UUIDs. This app uses `BSSC_` and
`c8a1xxxx`, and a different Android package (`com.bss.charger`). The two can run
on the same phone in the same room without either binding to the wrong device.
