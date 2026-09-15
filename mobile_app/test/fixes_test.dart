import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bss_gateway_monitor/faults.dart';
import 'package:bss_gateway_monitor/fixes.dart';

/// Station fault for `bit`, as decodeStation() would produce it.
FaultCode sta(int bit) =>
    decodeStation(1 << bit).firstWhere((f) => f.bit == bit);

/// Pod fault for `bit` on `slot`.
FaultCode pod(int bit, int slot) =>
    decodePod(1 << bit, slot).firstWhere((f) => f.bit == bit);

final DateTime t0 = DateTime(2026, 8, 30, 12, 0, 0);

void main() {
  group('wordCode', () {
    test('is the firmware string, not the display label', () {
      // The whole point: the gateway strcmp's against these.
      expect(sta(4).code, 'STA-05');
      expect(sta(4).wordCode, 'RS485_DEAD');
      expect(pod(1, 2).code, 'POD-02');
      expect(pod(1, 2).wordCode, 'LOCK_FAIL');
    });

    test('every named bit round-trips through the reverse lookup', () {
      for (var b = 0; b < kStaCode.length; b++) {
        expect(staBitForCode(sta(b).wordCode), b);
      }
      for (var b = 0; b < kPodCode.length; b++) {
        expect(podBitForCode(pod(b, 1).wordCode), b);
      }
    });

    test('an unnamed station bit falls back to the firmware default', () {
      expect(sta(20).code, 'STA-21');
      expect(sta(20).wordCode, kStaCodeUnknown);
    });
  });

  group('fixesFor — station faults', () {
    test('offers the exact op the firmware fix branch handles', () {
      for (final (bit, code, label) in [
        (2, 'CLOUD_DOWN', 'RECONNECT'),
        (3, 'WIFI_DOWN', 'RECONNECT'),
        (1, 'TIME_UNSYNCED', 'RE-SYNC'),
      ]) {
        final fixes = fixesFor(sta(bit), totalPods: 2);
        expect(fixes, hasLength(1), reason: code);
        expect(fixes.single.label, label);
        expect(fixes.single.kind, FixKind.stationFix);
        expect(json.decode(fixes.single.payload),
            {'cmd': 'fix', 'op': 'fix', 'code': code});
        expect(fixes.single.needsConfirm, isFalse,
            reason: 'a reconnect interrupts nothing an operator cares about');
      }
    });

    test('sticky latches offer clear-first, then reboot', () {
      for (final (bit, code) in [
        (6, 'BROWNOUT'),
        (5, 'REBOOT_ABNORMAL'),
        (9, 'LOW_HEAP'),
      ]) {
        final fixes = fixesFor(sta(bit), totalPods: 2);
        expect(fixes, hasLength(2), reason: code);
        expect(fixes.first.kind, FixKind.ack,
            reason: 'the non-destructive option must come first');
        expect(json.decode(fixes.first.payload),
            {'cmd': 'ack', 'op': 'ack', 'code': code});
        expect(fixes.first.needsConfirm, isFalse);

        expect(fixes.last.kind, FixKind.reboot);
        expect(json.decode(fixes.last.payload),
            {'cmd': 'reboot', 'op': 'reboot'});
        expect(fixes.last.needsConfirm, isTrue,
            reason: 'a reboot drops every pod session');
      }
    });

    test('offers nothing for faults no command can fix', () {
      // RS485_DEAD, SD_FAULT, AUDIO_FAULT, QUEUE_FULL need a human.
      for (final bit in [0, 4, 7, 8]) {
        expect(fixesFor(sta(bit), totalPods: 2), isEmpty,
            reason: sta(bit).wordCode);
      }
      // And an unnamed bit certainly gets nothing.
      expect(fixesFor(sta(25), totalPods: 2), isEmpty);
    });

    test('the offered set matches the firmware ladders exactly', () {
      // Guards against a code being added to one table but not the other.
      final offered = <String>{};
      for (var b = 0; b < 32; b++) {
        if (fixesFor(sta(b), totalPods: 2).isNotEmpty) {
          offered.add(sta(b).wordCode);
        }
      }
      expect(offered, {...kStationFixLabels.keys, ...kAckableCodes});
    });
  });

  group('fixesFor — pod faults', () {
    test('lock faults offer the unlock pulse with the right slot', () {
      for (final bit in [1, 2]) {
        final fixes = fixesFor(pod(bit, 2), totalPods: 2);
        expect(fixes, hasLength(1), reason: pod(bit, 2).wordCode);
        expect(fixes.single.kind, FixKind.podUnlock);
        expect(json.decode(fixes.single.payload),
            {'cmd': 'pod_action', 'op': 'pod_action',
             'slot': 2, 'action': 'unlock'});
        expect(fixes.single.needsConfirm, isTrue,
            reason: 'it physically releases a battery');
      }
    });

    test('withholds the unlock for a slot the gateway would reject', () {
      // BLE_handler.cpp validates slot against SEND_QUERY_SLAVE_SIZE, so on a
      // 2-pod station slot 3 is always "status":"error". Do not offer it.
      expect(fixesFor(pod(1, 3), totalPods: 2), isEmpty);
      expect(fixesFor(pod(1, 2), totalPods: 2), isNotEmpty);
      // And slot 3 IS offered on a station that actually has three pods.
      expect(fixesFor(pod(1, 3), totalPods: 3), isNotEmpty);
    });

    test('withholds the unlock before the pod count is known', () {
      // Guessing here would put a button on screen that always errors.
      expect(fixesFor(pod(1, 1), totalPods: 0), isEmpty);
    });

    test('other pod faults offer nothing', () {
      for (final bit in [0, 3, 4, 5, 6, 7]) {
        expect(fixesFor(pod(bit, 1), totalPods: 2), isEmpty,
            reason: pod(bit, 1).wordCode);
      }
    });

    test('both lock faults on one pod share a cooldown key', () {
      // One unlock pulse resolves either, so pressing one must damp the other.
      final a = fixesFor(pod(1, 2), totalPods: 2).single;
      final b = fixesFor(pod(2, 2), totalPods: 2).single;
      expect(a.key, b.key);
      // Different pods stay independent.
      expect(fixesFor(pod(1, 1), totalPods: 2).single.key, isNot(a.key));
      expect(json.decode(a.payload)['slot'], 2);
    });
  });

  group('FixCooldowns', () {
    test('blocks for ~5 s then reopens', () {
      final c = FixCooldowns();
      c.mark('fix:WIFI_DOWN', t0);
      expect(c.isCooling('fix:WIFI_DOWN', t0), isTrue);
      expect(c.isCooling('fix:WIFI_DOWN', t0.add(const Duration(seconds: 4))),
          isTrue);
      expect(c.isCooling('fix:WIFI_DOWN', t0.add(const Duration(seconds: 6))),
          isFalse);
      expect(kFixCooldown, const Duration(seconds: 5));
    });

    test('counts down to zero without going negative', () {
      final c = FixCooldowns();
      c.mark('reboot', t0);
      expect(c.remaining('reboot', t0), 5);
      expect(c.remaining('reboot', t0.add(const Duration(seconds: 4))), 1);
      expect(c.remaining('reboot', t0.add(const Duration(seconds: 30))), 0);
      expect(c.remaining('never-pressed', t0), 0);
    });

    test('keys are independent', () {
      final c = FixCooldowns();
      c.mark('fix:WIFI_DOWN', t0);
      expect(c.isCooling('fix:CLOUD_DOWN', t0), isFalse);
    });

    test('release reopens a button early', () {
      final c = FixCooldowns();
      c.mark('ack:BROWNOUT', t0);
      c.release('ack:BROWNOUT');
      expect(c.isCooling('ack:BROWNOUT', t0), isFalse);
    });
  });

  group('FixResult', () {
    test('reads each reply shape from §3.5', () {
      final r = FixResult.fromResponse({
        'op': 'pod_action', 'slot': 3, 'action': 'unlock', 'status': 'ok',
      })!;
      expect(r.ok, isTrue);
      expect(r.slot, 3);
      expect(r.key, 'pod_action:unlock:3');

      final f = FixResult.fromResponse(
          {'op': 'fix', 'code': 'CLOUD_DOWN', 'status': 'ok'})!;
      expect(f.key, 'fix:CLOUD_DOWN');

      final a = FixResult.fromResponse(
          {'op': 'ack', 'code': 'BROWNOUT', 'status': 'ok'})!;
      expect(a.key, 'ack:BROWNOUT');

      final b = FixResult.fromResponse({'op': 'reboot', 'status': 'ok'})!;
      expect(b.key, 'reboot');
    });

    test('a rejected op reports why', () {
      final r = FixResult.fromResponse(
          {'op': 'pod_action', 'slot': 9, 'action': 'unlock', 'status': 'error'})!;
      expect(r.ok, isFalse);
      expect(r.message, contains('pod 9'));
    });

    test('the key round-trips from the action that produced it', () {
      // A reply must be able to release the cooldown the press created.
      final action = fixesFor(pod(1, 2), totalPods: 2).single;
      final reply = FixResult.fromResponse({
        'op': 'pod_action', 'slot': 2, 'action': 'unlock', 'status': 'ok',
      })!;
      expect(reply.key, action.key);
    });

    test('ignores the other Response shapes', () {
      // §3.6 pushes a version object and a params dump down the same pipe.
      expect(FixResult.fromResponse({'type': 'version', 'fw_ver': '1.4.2'}),
          isNull);
      expect(FixResult.fromResponse({'op': 'params', 'wifi_ssid': 'AP'}),
          isNull);
      expect(FixResult.fromResponse({'op': 'set_param', 'key': 'wifi_ssid',
          'status': 'ok'}), isNull, reason: 'config ops are not fault fixes');
      // {"cmd":"reboot"} is now the CURRENT protocol, not a legacy echo, so it
      // must be recognised rather than dropped.
      expect(FixResult.fromResponse({'cmd': 'reboot', 'status': 'ok'})!.key,
          'reboot');
      expect(FixResult.fromResponse({'op': 'fix'}), isNull,
          reason: 'no status field');
    });
  });

  group('protocol key — "op" renamed to "cmd" on 2026-08-31', () {
    test('every command carries BOTH keys so either firmware accepts it', () {
      for (final p in [
        buildCommand('get_params'),
        buildCommand('save_reboot'),
        buildCommand('set_param', {'key': 'wifi_ssid', 'value': 'AP'}),
        fixesFor(sta(2), totalPods: 2).single.payload,
        fixesFor(pod(1, 1), totalPods: 2).single.payload,
        ...fixesFor(sta(6), totalPods: 2).map((a) => a.payload),
      ]) {
        final j = json.decode(p) as Map<String, dynamic>;
        expect(j['cmd'], isNotNull, reason: 'new firmware reads doc["cmd"]: $p');
        expect(j['op'], j['cmd'], reason: 'old firmware reads doc["op"]: $p');
      }
    });

    test('extra fields survive alongside the verb', () {
      final j = json.decode(buildCommand('set_param',
          {'key': 'mqtt_host', 'value': 'broker.example.com'}));
      expect(j, {
        'cmd': 'set_param', 'op': 'set_param',
        'key': 'mqtt_host', 'value': 'broker.example.com',
      });
    });

    test('replies are read under whichever key they arrive with', () {
      expect(commandVerb({'cmd': 'params'}), 'params');
      expect(commandVerb({'op': 'params'}), 'params');
      expect(commandVerb({'cmd': 'params', 'op': 'stale'}), 'params',
          reason: 'cmd wins — it is what current firmware sends');
      expect(commandVerb({'status': 'ok'}), isNull);
      expect(commandVerb({'cmd': 7}), isNull, reason: 'non-string is not a verb');
    });

    test('a fix reply parses from either generation', () {
      for (final j in [
        {'cmd': 'fix', 'code': 'WIFI_DOWN', 'status': 'ok'},
        {'op': 'fix', 'code': 'WIFI_DOWN', 'status': 'ok'},
      ]) {
        final r = FixResult.fromResponse(j)!;
        expect(r.ok, isTrue);
        expect(r.key, 'fix:WIFI_DOWN');
      }
    });
  });

  group('unlockActionFor — on-demand lock release', () {
    test('builds the same pod_action the firmware expects', () {
      final a = unlockActionFor(2, totalPods: 2)!;
      expect(a.kind, FixKind.podUnlock);
      expect(json.decode(a.payload), {
        'cmd': 'pod_action', 'op': 'pod_action',
        'slot': 2, 'action': 'unlock',
      });
      expect(a.needsConfirm, isTrue,
          reason: 'it physically releases a battery');
      expect(a.label, contains('2'),
          reason: 'the standalone button must name the slot it will open');
    });

    test('is offered for a healthy pod with no fault at all', () {
      // The whole point: the commonest reason to unlock is a customer who
      // cannot get their battery out, which reports nothing.
      for (var slot = 1; slot <= 2; slot++) {
        expect(unlockActionFor(slot, totalPods: 2), isNotNull);
      }
    });

    test('withheld for a slot the station does not have', () {
      expect(unlockActionFor(3, totalPods: 2), isNull);
      expect(unlockActionFor(0, totalPods: 2), isNull);
      expect(unlockActionFor(-1, totalPods: 2), isNull);
      expect(unlockActionFor(3, totalPods: 3), isNotNull);
    });

    test('withheld before the pod count is known', () {
      expect(unlockActionFor(1, totalPods: 0), isNull);
    });

    test('shares its cooldown key with the fault-driven button', () {
      // One pulse resolves either, so pressing UNLOCK on the pod page must damp
      // the UNLOCK on the Diagnostics page, and the reply must release both.
      final onDemand = unlockActionFor(2, totalPods: 2)!;
      final fromFault = fixesFor(pod(1, 2), totalPods: 2).single;
      expect(onDemand.key, fromFault.key);
      expect(onDemand.payload, fromFault.payload);

      final c = FixCooldowns();
      c.mark(onDemand.key, t0);
      expect(c.isCooling(fromFault.key, t0), isTrue);

      final reply = FixResult.fromResponse({
        'cmd': 'pod_action', 'slot': 2, 'action': 'unlock', 'status': 'error',
      })!;
      expect(reply.key, onDemand.key,
          reason: 'a rejection must release the button that sent it');
    });

    test('slots stay independent of each other', () {
      final a = unlockActionFor(1, totalPods: 2)!;
      final b = unlockActionFor(2, totalPods: 2)!;
      expect(a.key, isNot(b.key));
      final c = FixCooldowns();
      c.mark(a.key, t0);
      expect(c.isCooling(b.key, t0), isFalse);
    });
  });
}
