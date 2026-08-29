import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ble/charger_ble_service.dart';
import '../models/log_entry.dart';
import '../theme/palette.dart';
import '../widgets/common.dart';

/// Raw BLE traffic for the active charger link — the first thing to open when
/// a charger behaves oddly in the field.
class LogScreen extends StatelessWidget {
  final ChargerBleService service;
  const LogScreen({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final logs = service.logs.reversed.toList();
        return Scaffold(
          backgroundColor: P.logBg,
          appBar: AppBar(
            backgroundColor: P.card,
            title: Text('BLE log',
                style: TextStyle(
                    color: P.text, fontSize: 16.5, fontWeight: FontWeight.w700)),
            actions: [
              IconButton(
                tooltip: 'Copy all',
                icon: Icon(Icons.copy_all, color: P.textDim),
                onPressed: () {
                  final text = service.logs
                      .map((e) => '${_ts(e.ts)} ${_tag(e.type)} ${e.msg}')
                      .join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${service.logs.length} lines copied'),
                      backgroundColor: P.accent,
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: 'Clear',
                icon: Icon(Icons.delete_outline, color: P.textDim),
                onPressed: service.clearLogs,
              ),
            ],
          ),
          body: logs.isEmpty
              ? const EmptyState(
                  icon: Icons.terminal,
                  title: 'No traffic yet',
                  message: 'Reads, writes and notifications appear here as they happen.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: logs.length,
                  itemBuilder: (context, i) {
                    final e = logs[i];
                    final c = _color(e.type);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_ts(e.ts),
                              style: TextStyle(
                                color: P.textDim,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              )),
                          const SizedBox(width: 8),
                          Container(
                            width: 30,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            decoration: BoxDecoration(
                              color: c.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(_tag(e.type),
                                style: TextStyle(
                                    color: c,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              e.msg,
                              style: TextStyle(
                                color: e.type == LogType.err ? P.danger : P.text,
                                fontSize: 11.5,
                                fontFamily: 'monospace',
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  static String _ts(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  static String _tag(LogType t) => switch (t) {
        LogType.info => 'INF',
        LogType.tx => 'TX',
        LogType.rx => 'RX',
        LogType.err => 'ERR',
      };

  static Color _color(LogType t) => switch (t) {
        LogType.info => P.info,
        LogType.tx => P.warn,
        LogType.rx => P.success,
        LogType.err => P.danger,
      };
}
