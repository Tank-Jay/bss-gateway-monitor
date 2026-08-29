import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// GATT identifiers — must stay in lockstep with
/// `src/Charger_BLE_Handler/Charger_BLE_handler.h` and
/// `doc/Charger_BLE_Protocol.md`.
class ChargerUuids {
  // Services
  static final svcInfo = Guid('c8a10001-1234-4321-abcd-0123456789ab');
  static final svcBattery = Guid('c8a10002-1234-4321-abcd-0123456789ab');
  static final svcControl = Guid('c8a10003-1234-4321-abcd-0123456789ab');

  // Characteristics
  static final charInfo = Guid('c8a10101-1234-4321-abcd-0123456789ab');
  static final charBaySummary = Guid('c8a10201-1234-4321-abcd-0123456789ab');
  static final charBaySelect = Guid('c8a10202-1234-4321-abcd-0123456789ab');
  static final charBayDetail = Guid('c8a10203-1234-4321-abcd-0123456789ab');
  static final charCommand = Guid('c8a10301-1234-4321-abcd-0123456789ab');
  static final charResponse = Guid('c8a10302-1234-4321-abcd-0123456789ab');

  /// Advertised name prefix. Deliberately different from the gateway product
  /// (`BSSX_`) so neither app ever binds to the wrong device.
  static const namePrefix = 'BSSC_';

  /// Manufacturer identifier the charger broadcasts under.
  static const companyId = 0xFFFF;

  /// Wire-format version this app understands.
  static const protoVer = 0x01;

  /// Negotiated MTU — one bay-detail JSON must fit a single notification.
  static const mtu = 517;
}
