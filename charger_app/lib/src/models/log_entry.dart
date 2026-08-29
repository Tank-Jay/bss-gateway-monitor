enum LogType { info, tx, rx, err }

class LogEntry {
  final DateTime ts;
  final LogType type;
  final String msg;
  const LogEntry(this.ts, this.type, this.msg);
}

/// One point in a bay history buffer, used by the detail charts.
class BaySample {
  final DateTime t;
  final double soc;
  final double volts;
  final double amps;
  final double tempC;
  const BaySample({
    required this.t,
    required this.soc,
    required this.volts,
    required this.amps,
    required this.tempC,
  });
}
