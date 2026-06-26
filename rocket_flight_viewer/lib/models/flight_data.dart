import 'flight_sample.dart';

class FlightMetadata {
  final int fastPeriodMs;
  final int slowPeriodMs;
  final int fastCount;
  final int totalCount;
  final int preLaunchCount;       // samples before t=0 (launch detect), always at 20ms period
  final int groundRawPress;       // baro pressure snapshot at arm time; 0 = not available
  final int groundRawTemp;        // baro temperature snapshot at arm time; 0 = not available
  final double actualFastPeriodMs; // 0.0 = not available (no correction data)
  final int? slotIndex;            // PRO only: 0-7 flight slot this data was downloaded from
  final int baroType;               // 1=LPS22HB, 2=BMP581; defaults to LPS22HB for files predating this field

  const FlightMetadata({
    required this.fastPeriodMs,
    required this.slowPeriodMs,
    required this.fastCount,
    required this.totalCount,
    this.preLaunchCount = 0,
    this.groundRawPress = 0,
    this.groundRawTemp = 0,
    this.actualFastPeriodMs = 0.0,
    this.slotIndex,
    this.baroType = 1,
  });
}

class FlightData {
  final FlightMetadata metadata;
  final List<FlightSample> samples;

  const FlightData({required this.metadata, required this.samples});

  bool get isEmpty => samples.isEmpty;

  // Below this, the IMU is still reading resting gravity, not ignition
  // vibration or real motion. Deliberately well under the lowest possible
  // configured launch threshold (CONFIG_THR_MG_MIN = 500mg net -> 1.5g
  // total), so it never excludes a genuinely-resting sample for any valid
  // device configuration, while still catching real disturbance (ignition
  // vibration measured 1.7-3.3g in the tail of a real pre-launch buffer).
  static const double _restingAccelMagGMax = 1.3;

  // Ground reference pressure ("launch altitude"): average of the pre-launch
  // ring-buffer samples (~500ms immediately before launch) to average out
  // single-sample baro noise. Excludes any sample that already shows motion
  // — the firmware's multi-sample launch-confirm latches a few samples after
  // the IMU first sees ignition vibration, so the tail of the buffer can be
  // already-disturbed even though it's still labelled "pre-launch". This is
  // the one canonical reference every altitude calculation (stats, chart,
  // CSV) must use — falls back to the arm-time metadata snapshot, then the
  // first sample, if no clean pre-launch samples are available.
  int get groundRawPress {
    final n = metadata.preLaunchCount < samples.length
        ? metadata.preLaunchCount
        : samples.length;
    final resting =
        samples.take(n).where((s) => s.accelMagG < _restingAccelMagGMax);
    if (resting.isNotEmpty) {
      final sum = resting.fold<int>(0, (acc, s) => acc + s.rawPress);
      return (sum / resting.length).round();
    }
    if (metadata.groundRawPress != 0) return metadata.groundRawPress;
    return samples.isNotEmpty ? samples.first.rawPress : 0;
  }
}
