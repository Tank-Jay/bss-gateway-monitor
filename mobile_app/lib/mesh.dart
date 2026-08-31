/// BLE Mesh (Method 2) decode layer — doc/BLE_App_Integration.md §0 and §8.
///
/// The gateway ships two mutually exclusive BLE personalities, selected by
/// `CURRENT_BLE_METHOD` in src/Feature_Config.h:
///
///   BLE_METHOD_SINGLE (default) — GATT peripheral, one phone ↔ one station.
///                                 That is the rest of this app.
///   BLE_METHOD_MESH             — ESP-BLE-MESH node. No phone↔station GATT
///                                 link at all; every station publishes a
///                                 compact fault report into a mesh network.
///
/// This file decodes what a phone can observe of a mesh deployment. Like
/// faults.dart it imports no Flutter and no flutter_blue_plus, so all of it is
/// unit-testable — the UI hands it plain maps and byte lists.
///
/// WHAT A PHONE CAN AND CANNOT SEE
/// -------------------------------
/// src/Mesh_Handler/Mesh_handler.cpp brings each node up with
///
///     esp_ble_mesh_node_prov_enable(ESP_BLE_MESH_PROV_ADV | ESP_BLE_MESH_PROV_GATT)
///     config_server.gatt_proxy = ESP_BLE_MESH_GATT_PROXY_ENABLED
///
/// so a node is *visible* to an ordinary BLE scan throughout its life: it
/// advertises the Mesh Provisioning Service (0x1827) while unprovisioned and
/// the Mesh Proxy Service (0x1828) once a provisioner has adopted it. Both
/// carry Service Data this file parses, which is how [MeshBeacon] can tell you
/// a station is present, which station it is, and whether it has been
/// commissioned yet — with no keys of any kind.
///
/// The fault report itself is a different matter. It travels as an encrypted
/// mesh Network PDU, so reading it requires the network's NetKey and AppKey
/// plus a mesh crypto stack (k2/k4 derivation, header deobfuscation, two
/// layers of AES-CCM, and lower-transport reassembly). None of that is here.
/// [MeshStatus] therefore takes an already-decrypted access payload: point it
/// at whichever transport ends up carrying the data — a proxy client, or the
/// ESP32 forwarder described in §8.1 — and the rendering path is done.
library;

import 'dart:convert';

import 'faults.dart';

// ══════════════════════════════════════════════════════════════
//  Bluetooth Mesh service UUIDs
// ══════════════════════════════════════════════════════════════

/// Mesh Provisioning Service. Advertised by a node that has NOT been
/// provisioned yet (PB-GATT bearer).
const String kMeshProvisioningUuid = '1827';

/// Mesh Proxy Service. Advertised by a provisioned node whose GATT Proxy
/// feature is on — which the firmware always enables.
const String kMeshProxyUuid = '1828';

/// Reduce a Bluetooth UUID to the lowercase 4-hex short form when it sits in
/// the SIG base range, else to a plain lowercase 32-hex string.
///
/// flutter_blue_plus is not consistent about this across versions and
/// platforms: the same adopted service can arrive as `1827`, `0x1827`,
/// `00001827-0000-1000-8000-00805f9b34fb`, or that string uppercased. Matching
/// on any single spelling silently sees nothing on the platforms that use
/// another, and "no mesh nodes found" is indistinguishable from a real empty
/// scan — so every lookup goes through here first.
String normaliseUuid(String raw) {
  var s = raw.toLowerCase().replaceAll('-', '').replaceAll(' ', '');
  if (s.startsWith('0x')) s = s.substring(2);
  if (s.length == 32 &&
      s.startsWith('0000') &&
      s.endsWith('00001000800000805f9b34fb')) {
    return s.substring(4, 8);
  }
  if (s.length == 8 && s.startsWith('0000')) return s.substring(4);
  return s;
}

/// Look a service UUID up in a scan result's service-data map, tolerating
/// whatever spelling the platform used for the key.
List<int>? serviceDataFor(Map<String, List<int>> serviceData, String uuid) {
  final want = normaliseUuid(uuid);
  for (final e in serviceData.entries) {
    if (normaliseUuid(e.key) == want) return e.value;
  }
  return null;
}

// ══════════════════════════════════════════════════════════════
//  Device UUID — identifies which station a beacon came from
// ══════════════════════════════════════════════════════════════

/// The firmware's device-UUID signature.
///
///     static uint8_t dev_uuid[16] = { 0x32, 0x10 };
///     esp_read_mac(mac, ESP_MAC_BT);
///     memcpy(dev_uuid + 2, mac, 6);
///
/// So: two marker bytes, the 6-byte Bluetooth MAC, then eight zero bytes.
const List<int> kMeshDeviceUuidPrefix = [0x32, 0x10];

/// A 16-byte Bluetooth Mesh device UUID, as carried in an unprovisioned
/// node's beacon.
class MeshDeviceUuid {
  final List<int> bytes;

  const MeshDeviceUuid(this.bytes);

  /// True when this UUID carries the BSS firmware's `0x3210` marker, i.e. the
  /// node is one of ours and not somebody else's mesh hardware in range.
  bool get isBssStation =>
      bytes.length == 16 &&
      bytes[0] == kMeshDeviceUuidPrefix[0] &&
      bytes[1] == kMeshDeviceUuidPrefix[1];

  /// The station's Bluetooth MAC, `AA:BB:CC:DD:EE:FF`. Empty for a UUID that
  /// is not ours, where bytes 2..7 mean nothing.
  String get mac {
    if (!isBssStation) return '';
    return bytes
        .sublist(2, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  /// Last three MAC octets — enough to tell stations apart on a narrow row,
  /// and what the ESP32 prints in its own boot log.
  String get shortMac {
    if (!isBssStation) return '';
    return bytes
        .sublist(5, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  String get hex =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Parse exactly 16 bytes. Returns null on any other length rather than
  /// padding or truncating — a short UUID means the advertisement was
  /// malformed, and inventing bytes would fabricate a MAC.
  static MeshDeviceUuid? parse(List<int> b) =>
      b.length == 16 ? MeshDeviceUuid(List.unmodifiable(b)) : null;

  @override
  String toString() => isBssStation ? 'BSS $mac' : hex;
}

// ══════════════════════════════════════════════════════════════
//  Beacons
// ══════════════════════════════════════════════════════════════

/// What a mesh advertisement told us about the node that sent it.
enum MeshBeaconKind {
  /// Mesh Provisioning Service data: the node is up but no provisioner has
  /// adopted it. It is waiting to be commissioned (§8.2).
  unprovisioned,

  /// Mesh Proxy Service data, Network ID type. The node is provisioned and
  /// offering proxy service to anyone holding the network's keys.
  proxyNetworkId,

  /// Mesh Proxy Service data, Node Identity type. Provisioned, and
  /// advertising an identity hash so a specific client can recognise it.
  proxyNodeIdentity,

  /// Mesh service data we could not classify — a newer identification type
  /// (Mesh Protocol 1.1 added private identities) or a truncated payload.
  unknown,
}

/// One decoded mesh advertisement.
///
/// Layouts are from the Mesh Profile specification's service-data definitions:
///   0x1827 → 16-byte Device UUID + 2-byte OOB Information
///   0x1828 → 1-byte Identification Type, then
///              0x00 Network ID   : 8-byte network id
///              0x01 Node Identity: 8-byte hash + 8-byte random
class MeshBeacon {
  final MeshBeaconKind kind;

  /// Present only for [MeshBeaconKind.unprovisioned] — the proxy beacons
  /// deliberately do not carry the device UUID, so a provisioned node cannot
  /// be attributed to a station from its advertisement alone.
  final MeshDeviceUuid? deviceUuid;

  /// OOB Information bitmap from the provisioning beacon.
  final int? oobInfo;

  /// 8-byte Network ID, for [MeshBeaconKind.proxyNetworkId]. Two nodes on the
  /// same mesh advertise the same value, so it groups nodes by network.
  final List<int>? networkId;

  final List<int>? identityHash;
  final List<int>? identityRandom;

  const MeshBeacon({
    required this.kind,
    this.deviceUuid,
    this.oobInfo,
    this.networkId,
    this.identityHash,
    this.identityRandom,
  });

  bool get isProvisioned => kind == MeshBeaconKind.proxyNetworkId ||
      kind == MeshBeaconKind.proxyNodeIdentity;

  /// Decode from a scan result's service-data map. Returns null when the
  /// advertisement carries no mesh service data at all.
  ///
  /// Provisioning data is checked first: a node that is somehow advertising
  /// both is not yet commissioned, and the identifiable reading is the more
  /// useful one.
  static MeshBeacon? fromServiceData(Map<String, List<int>> serviceData) {
    final prov = serviceDataFor(serviceData, kMeshProvisioningUuid);
    if (prov != null) {
      // 16-byte UUID + 2-byte OOB. Some stacks omit the OOB field, so accept
      // 16 bytes as well rather than discarding an otherwise good UUID.
      if (prov.length >= 16) {
        return MeshBeacon(
          kind: MeshBeaconKind.unprovisioned,
          deviceUuid: MeshDeviceUuid.parse(prov.sublist(0, 16)),
          oobInfo: prov.length >= 18 ? (prov[16] << 8) | prov[17] : null,
        );
      }
      return const MeshBeacon(kind: MeshBeaconKind.unknown);
    }

    final proxy = serviceDataFor(serviceData, kMeshProxyUuid);
    if (proxy != null) {
      if (proxy.length >= 9 && proxy[0] == 0x00) {
        return MeshBeacon(
          kind: MeshBeaconKind.proxyNetworkId,
          networkId: List.unmodifiable(proxy.sublist(1, 9)),
        );
      }
      if (proxy.length >= 17 && proxy[0] == 0x01) {
        return MeshBeacon(
          kind: MeshBeaconKind.proxyNodeIdentity,
          identityHash: List.unmodifiable(proxy.sublist(1, 9)),
          identityRandom: List.unmodifiable(proxy.sublist(9, 17)),
        );
      }
      return const MeshBeacon(kind: MeshBeaconKind.unknown);
    }

    return null;
  }
}

// ══════════════════════════════════════════════════════════════
//  Vendor model
// ══════════════════════════════════════════════════════════════

/// Espressif's company id, `CID_ESP` in Mesh_handler.cpp.
const int kMeshCompanyId = 0x02E5;

/// `BSS_VND_MODEL_ID_SERVER` — the vendor model each node hosts.
const int kMeshVendorModelId = 0x0001;

/// On-wire bytes of `ESP_BLE_MESH_MODEL_OP_3(0x01, CID_ESP)`.
///
/// A 3-octet vendor opcode is `0xC0 | op` followed by the company id in
/// little-endian order, so 0x01 with CID 0x02E5 becomes C1 E5 02. The doc
/// quotes the same three bytes in §8.3.
const List<int> kMeshStatusOpcode = [0xC1, 0xE5, 0x02];

/// Strip the vendor status opcode from a decrypted access payload, returning
/// the JSON bytes behind it. Null when the opcode does not match, so traffic
/// from other models on the same network is ignored rather than mis-parsed.
List<int>? stripStatusOpcode(List<int> access) {
  if (access.length <= kMeshStatusOpcode.length) return null;
  for (var i = 0; i < kMeshStatusOpcode.length; i++) {
    if (access[i] != kMeshStatusOpcode[i]) return null;
  }
  return access.sublist(kMeshStatusOpcode.length);
}

/// Rebuild the operator text the firmware would have put in `main.msg`.
///
/// The mesh payload drops `msg` to stay small over the air (§8.3), so the app
/// regenerates it from the same tables the gateway used. Composition matches
/// Fault_MainError() exactly — `"Slot %u %s"` for a pod fault, the bare
/// station text otherwise — so a station reached over mesh and the same
/// station reached over GATT never word the same fault two different ways.
String meshMainMessage(String code, int slot) {
  if (code == 'OK') return '';
  final pb = podBitForCode(code);
  if (pb != null) return 'Slot $slot ${kPodText[pb]}';
  final sb = staBitForCode(code);
  if (sb != null) return kStaText[sb];
  if (code == kStaCodeUnknown) return kUnknownFaultText;
  return code;
}

// ══════════════════════════════════════════════════════════════
//  Status payload — §8.3
// ══════════════════════════════════════════════════════════════

/// One node's published fault report.
///
///     {"station":"Other","faultBits":16,"mainFault":"RS485_DEAD",
///      "faultSlot":0,"severity":2}
///
/// Built by Mesh_ContinousCheck() from the same fault engine as the GATT path
/// (Fault_GetBitmap / Fault_ComputePodBytes / Fault_MainError), which is why
/// [stationFaults] can reuse faults.dart's decoder unchanged.
class MeshStatus {
  /// `MESH_STATION_NAME` from Feature_Config.h. Note this is a build-time
  /// constant, so every station flashed from one image reports the same name —
  /// [MeshNode.label] prefers the MAC when it has one.
  final String station;

  /// uint32 station fault bitmap. Decode with the STA table (§4.1).
  final int faultBits;

  /// Headline word code — see [kStaCode] / [kPodCode], or `OK`.
  final String mainFault;

  /// Pod number for a pod-level `mainFault`, else 0.
  final int faultSlot;

  /// 2 = CRITICAL, 1 = WARNING, 0 = INFO.
  final int severity;

  /// When the app received this report — the payload carries no timestamp.
  final DateTime at;

  const MeshStatus({
    required this.station,
    required this.faultBits,
    required this.mainFault,
    required this.faultSlot,
    required this.severity,
    required this.at,
  });

  /// The only safe "nothing wrong" test, for the same reason as
  /// [MainFault.isOk]: LOW_HEAP is a real fault that also reports severity 0.
  bool get isOk => mainFault == 'OK';

  /// Every station bit currently set, decoded with the shared STA table.
  List<FaultCode> get stationFaults => decodeStation(faultBits);

  /// The same headline, in the shape the existing banner widget renders.
  MainFault get main => MainFault(
        code: mainFault,
        slot: faultSlot,
        sev: severity,
        msg: meshMainMessage(mainFault, faultSlot),
      );

  /// True when `mainFault` names a pod. The mesh payload does not carry the
  /// `pods[]` array (§8.3), so this slot number is the only per-pod
  /// information that survives the hop.
  bool get isPodFault => podBitForCode(mainFault) != null;

  factory MeshStatus.fromJson(Map<String, dynamic> j, {required DateTime at}) =>
      MeshStatus(
        station: (j['station'] as String?) ?? '',
        faultBits: (j['faultBits'] as num?)?.toInt() ?? 0,
        mainFault: (j['mainFault'] as String?) ?? 'OK',
        faultSlot: (j['faultSlot'] as num?)?.toInt() ?? 0,
        severity: (j['severity'] as num?)?.toInt() ?? 0,
        at: at,
      );

  /// Parse a decrypted access payload: opcode, then UTF-8 JSON.
  ///
  /// Returns null for anything that is not our vendor status — a foreign
  /// model, a truncated segment reassembly, or malformed JSON. A mesh network
  /// carries other traffic, so silence is the correct response to all three.
  static MeshStatus? fromAccessPayload(List<int> access,
      {required DateTime at}) {
    final body = stripStatusOpcode(access);
    if (body == null) return null;
    return fromJsonBytes(body, at: at);
  }

  /// Parse the JSON body on its own, for a transport that has already peeled
  /// the opcode off — the ESP32 forwarder of §8.1, for instance.
  static MeshStatus? fromJsonBytes(List<int> body, {required DateTime at}) {
    try {
      final decoded = json.decode(utf8.decode(body));
      if (decoded is! Map) return null;
      return MeshStatus.fromJson(decoded.cast<String, dynamic>(), at: at);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'MeshStatus($station, $mainFault/$faultSlot sev$severity, bits=$faultBits)';
}

// ══════════════════════════════════════════════════════════════
//  Node state
// ══════════════════════════════════════════════════════════════

/// A node is stale after ~5 missed publishes.
///
/// §8.4 asks for ~10 s and the publish period is 2 s, so this is the doc's
/// number and five chances to hit it. Mesh delivery is unacknowledged and
/// lossy by design; anything tighter reports healthy stations as gone.
const Duration kMeshStatusStale = Duration(seconds: 10);

/// A node whose advertisement has not been seen for this long has dropped off
/// the air. Beacons are far more frequent than publishes, but Android
/// coalesces duplicate advertisements aggressively, so this is deliberately
/// looser than [kMeshStatusStale].
const Duration kMeshBeaconStale = Duration(seconds: 30);

/// One mesh node as the app currently understands it.
class MeshNode {
  /// Scan identity — the BLE address the advertisement came from. Stable for
  /// the session, which is all this needs to key a map.
  final String id;

  final MeshBeaconKind kind;

  /// Set only from an unprovisioned beacon. Once a node is provisioned it
  /// stops advertising its device UUID, so this keeps whatever was learned
  /// while it was still unprovisioned and never regresses to null.
  final MeshDeviceUuid? deviceUuid;

  final int rssi;

  /// When the last advertisement arrived.
  final DateTime seenAt;

  /// Latest decrypted status, if a transport is supplying one.
  final MeshStatus? status;

  const MeshNode({
    required this.id,
    required this.kind,
    required this.rssi,
    required this.seenAt,
    this.deviceUuid,
    this.status,
  });

  bool get isProvisioned => kind == MeshBeaconKind.proxyNetworkId ||
      kind == MeshBeaconKind.proxyNodeIdentity;

  /// True when this is recognisably BSS firmware rather than someone else's
  /// mesh hardware. Only knowable while unprovisioned — see [deviceUuid].
  bool get isBssStation => deviceUuid?.isBssStation ?? false;

  /// Best available name: the published station name, else the MAC tail from
  /// the device UUID, else the raw scan id.
  String get label {
    final s = status?.station;
    if (s != null && s.isNotEmpty) return s;
    final m = deviceUuid?.shortMac;
    if (m != null && m.isNotEmpty) return 'Station $m';
    return id;
  }

  bool statusStaleAt(DateTime now) =>
      status == null || now.difference(status!.at) > kMeshStatusStale;

  bool beaconStaleAt(DateTime now) =>
      now.difference(seenAt) > kMeshBeaconStale;

  /// Severity for sorting and colouring. -1 when no status has arrived, so
  /// "unknown" sorts below INFO instead of impersonating a healthy node.
  int get sortSeverity => status == null ? -1 : status!.severity;

  MeshNode copyWith({
    MeshBeaconKind? kind,
    MeshDeviceUuid? deviceUuid,
    int? rssi,
    DateTime? seenAt,
    MeshStatus? status,
  }) =>
      MeshNode(
        id: id,
        kind: kind ?? this.kind,
        deviceUuid: deviceUuid ?? this.deviceUuid,
        rssi: rssi ?? this.rssi,
        seenAt: seenAt ?? this.seenAt,
        status: status ?? this.status,
      );
}

/// Keyed store of every mesh node the app has seen this session.
///
/// UPSERT ONLY, like FaultsStore, and for a related reason: a BLE scan reports
/// whichever nodes happened to advertise in the last window, not the full set.
/// Rebuilding the map from each batch would make the list flicker as nodes
/// take turns being heard.
class MeshStore {
  final Map<String, MeshNode> _byId = {};

  Iterable<MeshNode> get nodes => _byId.values;
  int get length => _byId.length;
  bool get isEmpty => _byId.isEmpty;

  MeshNode? operator [](String id) => _byId[id];

  /// Record an advertisement. Merges into any existing entry so a provisioned
  /// node keeps the device UUID it advertised before it was commissioned.
  void observe({
    required String id,
    required MeshBeacon beacon,
    required int rssi,
    required DateTime at,
  }) {
    final prev = _byId[id];
    _byId[id] = MeshNode(
      id: id,
      kind: beacon.kind,
      deviceUuid: beacon.deviceUuid ?? prev?.deviceUuid,
      rssi: rssi,
      seenAt: at,
      status: prev?.status,
    );
  }

  /// Attach a decrypted status report to a node, creating the entry if the
  /// report arrived over a transport that never produced a beacon (the §8.1
  /// forwarder reaches stations this phone cannot hear directly).
  void applyStatus(String id, MeshStatus status) {
    final prev = _byId[id];
    _byId[id] = prev == null
        ? MeshNode(
            id: id,
            kind: MeshBeaconKind.unknown,
            rssi: 0,
            seenAt: status.at,
            status: status,
          )
        : prev.copyWith(status: status);
  }

  void clear() => _byId.clear();

  /// Worst-first, then by name — the same ordering rule as the Diagnostics
  /// screen, so an operator reads both lists the same way.
  List<MeshNode> sorted() {
    final out = _byId.values.toList();
    out.sort((a, b) {
      final s = b.sortSeverity.compareTo(a.sortSeverity);
      if (s != 0) return s;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return out;
  }

  int get provisionedCount => _byId.values.where((n) => n.isProvisioned).length;

  int get unprovisionedCount =>
      _byId.values.where((n) => n.kind == MeshBeaconKind.unprovisioned).length;

  /// Nodes currently reporting a fault. Counts only nodes with a live status —
  /// a node we cannot decode is not evidence of health.
  int get faultedCount =>
      _byId.values.where((n) => n.status != null && !n.status!.isOk).length;

  /// Nodes that have delivered a status report at all, healthy or not.
  ///
  /// Distinct from [faultedCount] on purpose: zero faults means "every node
  /// reported and all are fine", zero statuses means "no node has reported".
  /// The UI has to tell those apart — conflating them puts a
  /// "reports not readable" warning on a depot that is simply healthy.
  int get statusCount => _byId.values.where((n) => n.status != null).length;

  bool anyCriticalAt(DateTime now) => _byId.values.any(
      (n) => !n.statusStaleAt(now) && (n.status?.severity ?? 0) >= 2);
}
