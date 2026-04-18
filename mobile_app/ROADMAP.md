# BSS Gateway Monitor — Feature Roadmap

Living document tracking current features and planned improvements for the Flutter mobile app.

---

## ✅ Current Features (v1.0)

### Authentication & Session
- [x] Login screen with username/password
- [x] Credentials: `Jaytank` / `Jay@2526` · `admin` / `admin`
- [x] Session persistence (SharedPreferences)
- [x] Sign out button

### BLE Connection
- [x] **Manual device picker** — bottom sheet with scan list, RSSI, MAC, filter
- [x] BSS-only / All-devices filter toggle
- [x] Permission handling (Bluetooth Scan/Connect + Location)
- [x] Bluetooth state check (warns if off)
- [x] Dual name detection (advertisement + scan response)
- [x] Connection state indicator (disconnected / scanning / connecting / connected)
- [x] Auto-discover 3 services + 6 characteristics

### Dashboard Tab
- [x] Station Info: station ID, version, WiFi/MQTT/SD status, free heap, faults, MAC, IP, RSSI
- [x] **Pod Summary with live auto-update every 1 sec** (via NOTIFY)
- [x] Per-pod cards: voltage, current, SOC bar, SOH, temperature, relay state
- [x] Color-coded values (green / orange / red based on thresholds)

### Pods Tab
- [x] Pod selector (1-5)
- [x] SOC progress bar with color coding
- [x] Full telemetry grid (pack V/I, SOH, cycles, min/max cell, available cap, relay)
- [x] 16 cell voltages with min (red) / max (green) highlighting
- [x] 6 NTC temperatures + 4 PDU temperatures
- [x] Pod NTC temp

### Log Tab
- [x] Timestamped TX/RX/INFO/ERR entries
- [x] Color-coded by type
- [x] Clear button
- [x] 200-entry rolling buffer

### Profile Tab
- [x] User avatar, name, role
- [x] Session stats (reads, BLE status, device name, FW version)
- [x] **Device Parameters** — read/edit WiFi SSID/pass, MQTT host/port/user/pass
- [x] **SAVE & REBOOT** to apply parameter changes
- [x] **Dark / Light theme toggle** (persistent)
- [x] Remote Control: Reboot / Factory Reset with confirmation dialogs
- [x] About section

---

## 🔴 HIGH Priority — Missing Essentials

### 1. Auto-reconnect
**Why:** Currently if BLE drops, user must tap Connect manually. Field deployments need resilience.

**Implementation:**
- Track last connected device MAC in SharedPreferences
- On disconnect, auto-scan for that MAC with 10s retry (configurable)
- Max retry count before giving up
- Toggle in Settings: "Auto-reconnect on disconnect"

**Effort:** Medium (2-3 hours)

---

### 2. Export / Share Data
**Why:** Service technicians need to capture BMS state for records / support tickets.

**Implementation:**
- "Export" button on Dashboard and Pods tabs
- Generate JSON or CSV snapshot of current state
- Use `share_plus` package to email / WhatsApp / save to file
- Include timestamp, station ID, firmware version in filename

**Effort:** Small (1-2 hours)

---

### 3. Push Notifications on Critical Events
**Why:** User needs to know about over-temperature, low SOC, fault states even when app is closed.

**Implementation:**
- `flutter_local_notifications` package
- Background BLE service (complex on Android — requires foreground service)
- Alert thresholds: Temp > 55°C, SOC < 15%, Fault bitmap != 0, Pod disconnect
- Sound + vibration
- Tappable to open app on that pod

**Effort:** Large (5-8 hours — foreground service is tricky)

---

### 4. Configurable Alarm Thresholds
**Why:** Different sites have different safety thresholds.

**Implementation:**
- New "Alarms" card in Profile tab
- Editable thresholds: Over-temp, Under-voltage, Low SOC, Cell imbalance (max-min delta)
- Visual alarm banner on Dashboard when threshold breached
- Per-pod vs station-wide alarms

**Effort:** Medium (2-3 hours)

---

### 5. Multi-Device Support
**Why:** Technicians service multiple stations — currently need to reconnect each time.

**Implementation:**
- "Known Devices" list in Profile tab
- Remember up to N paired devices with last-seen timestamps
- Quick-connect from the list (skip the scan step)
- Per-device custom label (e.g., "Warehouse A", "Site 42")

**Effort:** Medium (3-4 hours)

---

## 🟡 MEDIUM Priority — UX Polish

### 6. Historical Charts
**Why:** Trends tell more than live values. See voltage/current/SOC over time.

**Implementation:**
- `fl_chart` package for line graphs
- Circular buffer: last 10/30/60 minutes of samples
- Chart views on Pod Detail tab: V / I / SOC / Temp vs. time
- Optional SQLite persistence for longer history

**Effort:** Large (6-10 hours)

---

### 7. Pull-to-Refresh
**Why:** Standard mobile UX. Currently user must find the READ button.

**Implementation:**
- Wrap Dashboard body in `RefreshIndicator`
- Pull down triggers `readStationInfo()`
- Same for Pods tab

**Effort:** Trivial (30 min)

---

### 8. Swipeable Pod Pages
**Why:** Faster navigation between pods than tapping the number selector.

**Implementation:**
- `PageView.builder` in Pods tab instead of IndexedStack
- Page indicator dots
- Sync with pod selector buttons

**Effort:** Small (1-2 hours)

---

### 9. Search / Filter in Log
**Why:** Debugging specific events is hard with 200 entries scrolling.

**Implementation:**
- Search bar at top of Log tab
- Filter by type: TX / RX / INFO / ERR (multi-select chips)
- Live filtering as you type

**Effort:** Small (1-2 hours)

---

### 10. Sound / Vibration on Alarm
**Why:** Get user attention for critical faults.

**Implementation:**
- `vibration` package
- Custom alarm sound asset or system beep
- Only trigger on *new* alarms (debounce)

**Effort:** Small (1-2 hours)

---

### 11. Command History
**Why:** Repeat previous commands quickly (e.g., multiple reboots during testing).

**Implementation:**
- Keep last 20 sent commands
- Chip row at top of Log tab with quick-resend buttons
- Useful for developer/tester mode

**Effort:** Small (1 hour)

---

## 🟢 LOW Priority — Nice to Have

### 12. QR Code Pairing
**Why:** Cleaner than picking from device list, especially for non-technical users.

**Implementation:**
- ESP32 firmware prints/displays QR with MAC address
- `mobile_scanner` package for camera scan
- Scan → auto-connect to that MAC

**Effort:** Medium (3-4 hours, needs firmware support)

---

### 13. Firmware OTA Over BLE
**Why:** Update ESP32 firmware wirelessly without WiFi setup.

**Implementation:**
- New BLE service with chunked upload characteristic
- App picks .bin file from phone storage
- Progress bar during upload
- Signature verification on device side

**Effort:** Very Large (15-20 hours — non-trivial protocol)

---

### 14. Biometric Login
**Why:** Fingerprint / face unlock faster than typing password.

**Implementation:**
- `local_auth` package
- Toggle in Profile: "Use biometric to unlock"
- Store a flag, not credentials

**Effort:** Small (1-2 hours)

---

### 15. Multi-Language Support (i18n)
**Why:** Hindi / Gujarati / regional for field deployment.

**Implementation:**
- Flutter intl package
- `arb` files for each language
- Language picker in Profile

**Effort:** Medium (3-5 hours first time, small per-language)

---

### 16. Home Screen Widget
**Why:** Glance at Pod SOC without opening app.

**Implementation:**
- Android: `home_widget` package + native widget code
- Shows last known SOC from connected pod
- Updates hourly (BLE requires app-open for live)

**Effort:** Large (6-8 hours — platform-specific)

---

### 17. Voice Commands
**Why:** Accessibility for technicians with gloves / hands full.

**Implementation:**
- Integrate with Google Assistant / App Actions
- Shortcuts: "Read pod 2", "Reboot BSS"

**Effort:** Medium (4-6 hours)

---

### 18. Share Dashboard Screenshot
**Why:** Quick status sharing with team / customers via WhatsApp.

**Implementation:**
- `screenshot` package
- Capture Dashboard as image
- `share_plus` to share via any installed app

**Effort:** Trivial (1 hour)

---

## 🔵 TECHNICAL Improvements

### 19. App Icon + Splash Screen
**Why:** Currently uses default Flutter icon. Looks unprofessional.

**Implementation:**
- Design 1024x1024 PNG icon
- Use `flutter_launcher_icons` package to generate all sizes
- `flutter_native_splash` for splash screen

**Effort:** Trivial (1 hour + design time)

---

### 20. Crash Reporting
**Why:** Know when users hit bugs without them reporting.

**Implementation:**
- Firebase Crashlytics integration
- Or Sentry (simpler, free tier)

**Effort:** Small (2 hours)

---

### 21. Analytics
**Why:** Data-driven decisions — which tabs / features are actually used?

**Implementation:**
- Firebase Analytics or Umami (privacy-friendly)
- Track screen views, button taps, connection success rate

**Effort:** Small (2 hours)

---

### 22. iOS Support
**Why:** Currently Android-only — many users have iPhones.

**Implementation:**
- Generate iOS scaffolding (`flutter create --platforms ios .`)
- Add Info.plist BLE permission descriptions
- Build + distribute via TestFlight (requires Apple Developer account $99/yr)

**Effort:** Medium (4-6 hours) + ongoing Apple cert maintenance

---

### 23. Play Store Release
**Why:** Easier distribution than APK-by-email. Auto-updates for users.

**Implementation:**
- Generate signing keystore
- Configure release signing in `android/app/build.gradle`
- Create Play Console account ($25 one-time)
- Upload signed AAB, fill listing metadata, screenshots

**Effort:** Medium (4-6 hours) + review wait (~2 days)

---

### 24. Settings Persistence
**Why:** Currently auto-connect, verbose, theme are the only persisted prefs.

**Implementation:**
- Expose all configurable options in Settings
- Group them: "Connection", "Display", "Alarms", "Developer"
- Reset to defaults button

**Effort:** Small (2 hours)

---

### 25. Dependency Injection / State Management
**Why:** Current app uses a single `BleService` ChangeNotifier. Harder to test / scale.

**Implementation:**
- Migrate to Riverpod or Provider
- Separate concerns: BLE layer, domain layer, UI layer
- Add unit tests

**Effort:** Large (8-12 hours — refactor)

---

## 📋 Feature Priority Matrix

| Priority | Feature | Effort | Dependencies |
|----------|---------|--------|--------------|
| 🔴 HIGH  | Auto-reconnect | M | None |
| 🔴 HIGH  | Export / Share | S | None |
| 🔴 HIGH  | Push notifications | L | Foreground service |
| 🔴 HIGH  | Alarm thresholds | M | None |
| 🔴 HIGH  | Multi-device support | M | None |
| 🟡 MED   | Historical charts | L | fl_chart package |
| 🟡 MED   | Pull-to-refresh | XS | None |
| 🟡 MED   | Swipeable pods | S | None |
| 🟡 MED   | Log search/filter | S | None |
| 🟡 MED   | Alarm sound/vibration | S | None |
| 🟡 MED   | Command history | S | None |
| 🟢 LOW   | QR pairing | M | Firmware change |
| 🟢 LOW   | OTA over BLE | XL | New BLE service |
| 🟢 LOW   | Biometric login | S | None |
| 🟢 LOW   | i18n | M | None |
| 🟢 LOW   | Home widget | L | Platform-specific |
| 🟢 LOW   | Voice commands | M | Google APIs |
| 🟢 LOW   | Screenshot share | XS | None |
| 🔵 TECH  | App icon + splash | XS | Design |
| 🔵 TECH  | Crashlytics | S | Firebase |
| 🔵 TECH  | Analytics | S | Firebase |
| 🔵 TECH  | iOS support | M | Apple Dev acct |
| 🔵 TECH  | Play Store release | M | Google Play acct |
| 🔵 TECH  | Settings persistence | S | None |
| 🔵 TECH  | Refactor state mgmt | L | None |

**Effort legend:** XS = <1h · S = 1-2h · M = 3-4h · L = 6-10h · XL = 15h+

---

## 🎯 Suggested Next Release (v1.1)

Focus on the high-value, low-effort items:

1. **Pull-to-refresh** (30 min) — instant UX win
2. **Export as JSON/CSV** (2 hr) — frequently needed
3. **Auto-reconnect** (3 hr) — resilience
4. **Alarm thresholds** (3 hr) — safety
5. **App icon + splash** (1 hr + design) — professional polish

**Total effort:** ~10 hours · **User impact:** Very High

---

## 🚀 Long-Term Vision (v2.0+)

- Multi-device fleet management (map view of all BSS stations)
- OTA firmware updates over BLE
- Cloud sync for historical data (MQTT already exists — just persist to cloud)
- iOS + Play Store releases
- Real-time collaboration (2 technicians on same device)
- AI anomaly detection (detect unusual patterns before failure)

---

## 📝 Contributing

When implementing a feature from this roadmap:
1. Move it from TODO → "In Progress" section
2. Create a branch `feature/NN-feature-name`
3. Push commits — GitHub Actions auto-builds APK
4. Test on physical device
5. Move to "✅ Current Features" when merged

_Last updated: 2026-04-18_
