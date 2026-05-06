import 'package:flutter/material.dart';
import '../models/bmp384_calib.dart';
import '../models/flight_stats.dart';

class StatsWidget extends StatelessWidget {
  final FlightStats stats;
  final Bmp384Calib? calib;

  const StatsWidget({super.key, required this.stats, this.calib});

  @override
  Widget build(BuildContext context) {
    final c = calib;

    // Max altitude: use pre-computed value from fromData(); show dash if unavailable.
    final altM = stats.maxAltM;
    final maxAltStr = altM != null
        ? '${altM.toStringAsFixed(1)} m  /  ${(altM * 3.28084).toStringAsFixed(1)} ft'
        : c == null ? '— (no calibration)' : '— (no data)';

    // Arm altitude (absolute MSL reference)
    String armAlt = '—';
    if (c != null && stats.groundRawPress != 0) {
      final groundTLin = stats.groundRawTemp != 0
          ? c.tLin(stats.groundRawTemp)
          : 25.0;
      final pa = c.pressurePa(stats.groundRawPress, groundTLin);
      final m  = Bmp384Calib.altitudeM(pa);
      armAlt = '${m.toStringAsFixed(1)} m  /  ${(m * 3.28084).toStringAsFixed(1)} ft'
               '  (raw: ${stats.groundRawPress})';
    }

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
              const Divider(),
              _row('Flight time',           _ms(stats.flightTimeMs, orElse: '— (no data)')),
              if (stats.timeBurnoutMs > 0)
                _row('Burnout (from launch)', _ms(stats.timeBurnoutMs)),
              _row('Apogee (from launch)',  _ms(stats.timeApogeeMs)),
              _row('Landing (from launch)', _ms(stats.timeRecoveryMs)),
              const Divider(),
              _row('Max acceleration',
                  stats.maxAccelMg > 0
                      ? '${(stats.maxAccelMg / 1000.0).toStringAsFixed(2)} g'
                      : '—'),
              _row('Max altitude', maxAltStr),
              const Divider(),
              _row('Arm pressure (raw)',
                  '0x${stats.groundRawPress.toRadixString(16).toUpperCase().padLeft(6, '0')}  (${stats.groundRawPress})'),
              _row('Arm altitude (abs)', armAlt),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 180,
              child: Text(label, style: const TextStyle(color: Colors.grey)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      );

  String _ms(int ms, {String orElse = '— (not detected)'}) {
    if (ms == 0) return orElse;
    return '${(ms / 1000.0).toStringAsFixed(3)} s';
  }
}
