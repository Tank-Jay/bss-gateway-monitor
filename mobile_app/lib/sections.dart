// ══════════════════════════════════════════════════════════════
//  sections.dart - the two things this app can monitor
//
//  The app has always done two unrelated jobs: watch ONE station over a
//  direct BLE link, and survey MANY stations advertising as mesh nodes.
//  The second was buried at the bottom of Profile, so it read as a setting
//  rather than as the separate mode it is. They are split here, at the
//  front door, and named for what they show.
//
//  Only the single-station section works against the gateway firmware in
//  this repo. That firmware is a plain GATT peripheral - it has no mesh
//  stack, no CURRENT_BLE_METHOD, nothing to provision - so the mesh
//  section scans and finds nothing until a gateway is flashed with a mesh
//  build. The card says so plainly, because an empty list with no
//  explanation reads as a broken radio or a broken phone.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'theme.dart';

class SectionScreen extends StatelessWidget {
  const SectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tone.of(context);

    return Scaffold(
      backgroundColor: t.bg,
      body: Container(
        decoration: BoxDecoration(gradient: t.backdrop),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BSS Gateway',
                          style: TextStyle(
                            fontFamily: AppFonts.ui,
                            fontSize: AppSize.fxl,
                            fontWeight: FontWeight.w800,
                            color: t.gold,
                            letterSpacing: AppTracking.tight,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text('MONITOR', style: AppText.caps(t)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sign out',
                    onPressed: () => _signOut(context),
                    icon: Icon(Icons.logout, size: 20, color: t.textSoft),
                  ),
                ],
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(4, 22, 4, 11),
                child: Text('CHOOSE A SECTION', style: AppText.sectionLabel(t)),
              ),

              _SectionCard(
                icon: Icons.ev_station_outlined,
                title: 'One Station Data',
                subtitle: 'Single station over BLE',
                body: 'Connect to one station and watch it live: every pod '
                    'SOC, voltage and temperature, cell detail, faults with '
                    'one-tap fixes, door locks and cabinet health.',
                badge: 'READY',
                badgeColor: t.green,
                primary: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                ),
              ),

              const SizedBox(height: 14),

              _SectionCard(
                icon: Icons.hub_outlined,
                title: 'Mesh Station Data',
                subtitle: 'Many stations as mesh nodes',
                body: 'Surveys stations advertising on BLE Mesh and shows '
                    'which are provisioned, which are faulted, and which have '
                    'gone quiet.',
                badge: 'NEEDS MESH FIRMWARE',
                badgeColor: t.amber,
                primary: false,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MeshScreen()),
                ),
              ),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(13),
                decoration: appTint(t.amber, radius: AppRadius.rSm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 17, color: t.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Gateways on the current firmware are single-link GATT '
                        'peripherals, not mesh nodes. Use One Station Data. '
                        'The mesh section stays empty until a gateway is '
                        'flashed with a mesh build.',
                        style: TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: AppSize.fxs,
                          height: 1.45,
                          color: t.textMid,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Clears the whole stack, not just the top route. Signing out from a
  /// screen pushed above this one must not leave the section list sitting
  /// underneath the login form, reachable with the back gesture.
  void _signOut(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bss_auth');
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (r) => false,
      );
    }
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle, body, badge;
  final Color badgeColor;

  /// The section that actually works against current firmware. It gets the
  /// gold border and tinted glyph; the other stays neutral. That contrast
  /// is the whole message of this screen.
  final bool primary;
  final VoidCallback onTap;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.badge,
    required this.badgeColor,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tone.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rMd,
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: appCard(t, borderColor: primary ? t.goldBorder : null),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: primary ? t.goldLight : t.card2,
                      borderRadius: AppRadius.rSm,
                      border:
                          Border.all(color: primary ? t.goldBorder : t.border),
                    ),
                    child: Icon(icon,
                        size: 22, color: primary ? t.gold : t.textSoft),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: AppFonts.ui,
                            fontSize: AppSize.flg,
                            fontWeight: FontWeight.w800,
                            color: t.text,
                            letterSpacing: AppTracking.tight,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontFamily: AppFonts.ui,
                            fontSize: AppSize.fxs,
                            color: t.textSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 22, color: t.textSoft),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                body,
                style: TextStyle(
                  fontFamily: AppFonts.ui,
                  fontSize: AppSize.fxs,
                  height: 1.5,
                  color: t.textMid,
                ),
              ),
              const SizedBox(height: 13),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: appTint(badgeColor, radius: AppRadius.rFull),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: AppSize.f2xs,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                    letterSpacing: AppTracking.chip,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
