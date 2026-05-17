import 'flight_sample.dart';

class FlightMetadata {
  final int fastPeriodMs;
  final int slowPeriodMs;
  final int fastCount;
  final int totalCount;
  final int groundRawPress;       // baro pressure snapshot at arm time; 0 = not available
  final int groundRawTemp;        // baro temperature snapshot at arm time; 0 = not available
  final double actualFastPeriodMs; // 0.0 = not available (no correction data)

  const FlightMetadata({
    required this.fastPeriodMs,
    required this.slowPeriodMs,
    required this.fastCount,
    required this.totalCount,
    this.groundRawPress = 0,
    this.groundRawTemp = 0,
    this.actualFastPeriodMs = 0.0,
  });
}

class FlightData {
  final FlightMetadata metadata;
  final List<FlightSample> samples;

  const FlightData({required this.metadata, required this.samples});

  bool get isEmpty => samples.isEmpty;

  // Ground reference pressure: arm-time snapshot if available, else first sample.
  int get groundRawPress => (metadata.groundRawPress != 0)
      ? metadata.groundRawPress
      : (samples.isNotEmpty ? samples.first.rawPress : 0);

  // Positive delta = higher than ground (lower pressure).
  int deltaPress(FlightSample s) => groundRawPress - s.rawPress;
}
