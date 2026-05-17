import 'package:flutter/material.dart';
import '../models/bmp384_calib.dart';
import '../models/flight_stats.dart';

class StatsWidget extends StatelessWidget {
  final FlightStats stats;
  final Bmp384Calib? calib;
  final FlightStats? stats2;
  final Color colorA;
  final Color colorB;

  const StatsWidget({
    super.key,
    required this.stats,
    this.calib,
    this.stats2,
    this.colorA = Colors.blue,
    this.colorB = Colors.pinkAccent,
  });

  @override
  Widget build(BuildContext context) {
    return stats2 != null
        ? _buildComparison(context)
        : _buildSingle(context);
  }

  Widget _buildSingle(BuildContext context) {
    final c = calib;
    final altM = stats.maxAltM;
    final maxAltStr = altM != null
        ? '${altM.toStringAsFixed(1)} m  /  ${(altM * 3.28084).toStringAsFixed(1)} ft'
        : c == null ? '— (no calibration)' : '— (no data)';

    String armAlt = '—';
    if (c != null && stats.groundRawPress != 0) {
      final groundTLin = stats.groundRawTemp != 0 ? c.tLin(stats.groundRawTemp) : 25.0;
      final pa = c.pressurePa(stats.groundRawPress, groundTLin);
      final m  = Bmp384Calib.altitudeM(pa);
      armAlt = '${m.toStringAsFixed(1)} m  /  ${(m * 3.28084).toStringAsFixed(1)} ft';
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[400]!;

    Widget labelCell(String text) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(text,
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        );

    Widget valueCell(String text) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(text,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
        );

    TableRow dataRow(String label, String value) =>
        TableRow(children: [labelCell(label), valueCell(value)]);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Flight Stats', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Table(
                border: TableBorder.all(color: borderColor, width: 0.5),
                columnWidths: const {
                  0: FlexColumnWidth(1.4),
                  1: FlexColumnWidth(2.0),
                },
                children: [
                  dataRow('Flight time', _ms(stats.flightTimeMs, orElse: '— (no data)')),
                  if (stats.timeBurnoutMs > 0)
                    dataRow('Burnout', _ms(stats.timeBurnoutMs)),
                  dataRow('Apogee', _ms(stats.timeApogeeMs)),
                  dataRow('Landing', _ms(stats.timeRecoveryMs)),
                  dataRow('Max acceleration',
                      stats.maxAccelMg > 0
                          ? '${(stats.maxAccelMg / 1000.0).toStringAsFixed(2)} g'
                          : '—'),
                  dataRow('Max altitude', maxAltStr),
                  dataRow('Arm altitude', armAlt),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComparison(BuildContext context) {
    final s2 = stats2!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? Colors.grey[850]! : Colors.grey[200]!;
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[400]!;

    String altStr(FlightStats s) {
      final altM = s.maxAltM;
      return altM != null
          ? '${altM.toStringAsFixed(1)} m / ${(altM * 3.28084).toStringAsFixed(1)} ft'
          : '— (no data)';
    }

    String deltaMs(int msA, int msB) {
      if (msA == 0 || msB == 0) return '—';
      final d = (msA - msB) / 1000.0;
      return '${d >= 0 ? '+' : ''}${d.toStringAsFixed(3)} s';
    }

    String deltaAltStr() {
      final altA = stats.maxAltM;
      final altB = s2.maxAltM;
      if (altA == null || altB == null) return '—';
      final d = altA - altB;
      final sign = d >= 0 ? '+' : '';
      return '$sign${d.toStringAsFixed(1)} m / $sign${(d * 3.28084).toStringAsFixed(1)} ft';
    }

    String deltaAccelStr() {
      if (stats.maxAccelMg == 0 || s2.maxAccelMg == 0) return '—';
      final d = (stats.maxAccelMg - s2.maxAccelMg) / 1000.0;
      return '${d >= 0 ? '+' : ''}${d.toStringAsFixed(2)} g';
    }

    Widget headerCell(String text, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(text,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: color)),
        );

    Widget labelCell(String text) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(text,
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        );

    Widget valueCell(String text, Color color) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(text,
              style: TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 12, color: color)),
        );

    Widget deltaCell(String text) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(text,
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        );

    TableRow dataRow(String label, String a, String b, String delta) =>
        TableRow(children: [
          labelCell(label),
          valueCell(a, colorA),
          valueCell(b, colorB),
          deltaCell(delta),
        ]);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Flight Stats',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Table(
                border: TableBorder.all(color: borderColor, width: 0.5),
                columnWidths: const {
                  0: FlexColumnWidth(1.4),
                  1: FlexColumnWidth(1.1),
                  2: FlexColumnWidth(1.1),
                  3: FlexColumnWidth(1.2),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: headerBg),
                    children: [
                      headerCell(''),
                      headerCell('Flight A', color: colorA),
                      headerCell('Flight B', color: colorB),
                      headerCell('Δ (A−B)', color: Colors.grey[500]),
                    ],
                  ),
                  dataRow('Flight time',
                      _ms(stats.flightTimeMs, orElse: '—'),
                      _ms(s2.flightTimeMs, orElse: '—'),
                      deltaMs(stats.flightTimeMs, s2.flightTimeMs)),
                  if (stats.timeBurnoutMs > 0 || s2.timeBurnoutMs > 0)
                    dataRow('Burnout',
                        _ms(stats.timeBurnoutMs, orElse: '—'),
                        _ms(s2.timeBurnoutMs, orElse: '—'),
                        deltaMs(stats.timeBurnoutMs, s2.timeBurnoutMs)),
                  dataRow('Apogee',
                      _ms(stats.timeApogeeMs),
                      _ms(s2.timeApogeeMs),
                      deltaMs(stats.timeApogeeMs, s2.timeApogeeMs)),
                  dataRow('Landing',
                      _ms(stats.timeRecoveryMs),
                      _ms(s2.timeRecoveryMs),
                      deltaMs(stats.timeRecoveryMs, s2.timeRecoveryMs)),
                  dataRow('Max acceleration',
                      stats.maxAccelMg > 0
                          ? '${(stats.maxAccelMg / 1000.0).toStringAsFixed(2)} g'
                          : '—',
                      s2.maxAccelMg > 0
                          ? '${(s2.maxAccelMg / 1000.0).toStringAsFixed(2)} g'
                          : '—',
                      deltaAccelStr()),
                  dataRow('Max altitude', altStr(stats), altStr(s2),
                      deltaAltStr()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _ms(int ms, {String orElse = '— (not detected)'}) {
    if (ms == 0) return orElse;
    return '${(ms / 1000.0).toStringAsFixed(3)} s';
  }
}
