import 'dart:math';
import 'lps22hb.dart' as lps22hb;
import 'flight_data.dart';

class FlightStats {
  final int flightTimeMs;
  final int maxAccelMg;
  final int minRawPress;
  final int timeBurnoutMs;
  final int timeApogeeMs;
  final int timeRecoveryMs;
  final int groundRawPress;   // baro pressure at arm time; 0 = not recorded
  final int groundRawTemp;    // baro temperature at arm time; 0 = not recorded
  final double? maxAltM;      // max altitude above ground
  final int baroType;         // 1=LPS22HB, 2=BMP581 — needed to scale groundRawPress to an absolute MSL altitude
  final int ignitionOffsetMs; // true-ignition shift applied to all *Ms fields above — see FlightData.ignitionOffsetMs

  const FlightStats({
    required this.flightTimeMs,
    required this.maxAccelMg,
    required this.minRawPress,
    required this.timeBurnoutMs,
    required this.timeApogeeMs,
    required this.timeRecoveryMs,
    this.groundRawPress = 0,
    this.groundRawTemp = 0,
    this.maxAltM,
    this.baroType = 1,
    this.ignitionOffsetMs = 0,
  });

  factory FlightStats.fromData(FlightData data) {
    final samples = data.samples;
    if (samples.isEmpty) {
      return FlightStats(
        flightTimeMs: 0, maxAccelMg: 0, minRawPress: 0,
        timeBurnoutMs: 0, timeApogeeMs: 0, timeRecoveryMs: 0,
        groundRawPress: data.groundRawPress,
        groundRawTemp: data.metadata.groundRawTemp,
        baroType: data.metadata.baroType,
      );
    }

    // Burnout: first high→low crossing of 1300 mg in the fast phase.
    // Threshold sits above resting gravity (1000 mg) but below any meaningful
    // powered phase. Slow-phase samples (1 Hz) are too coarse for detection.
    int burnoutIdx = 0;
    int timeBurnoutMs = 0;
    const burnoutThreshMg = 1300;
    // samples[] has preLaunchCount pre-launch entries prepended before the
    // fast phase (see payload_service.dart's `fi = i - preLaunchCount`) — the
    // fast phase itself runs from preLaunchCount to preLaunchCount+fastCount.
    final fastStart = min(data.metadata.preLaunchCount, samples.length);
    final fastEnd = min(
        data.metadata.preLaunchCount + data.metadata.fastCount,
        samples.length);
    bool seenPowered = false;
    for (int i = fastStart; i < fastEnd; i++) {
      final mg = (samples[i].accelMagG * 1000).round();
      if (!seenPowered) {
        if (mg >= burnoutThreshMg) seenPowered = true;
      } else if (mg < burnoutThreshMg) {
        burnoutIdx = i;
        timeBurnoutMs = samples[i].timeMs;
        break;
      }
    }

    // Max accel: boost phase only (up to burnout) so chute deployment and
    // landing spikes don't inflate the stat. Fall back to full fast phase
    // if burnout wasn't detected.
    final boostEnd = burnoutIdx > 0 ? burnoutIdx : fastEnd;
    double maxAccelG = 0;
    for (int i = fastStart; i < boostEnd; i++) {
      final g = samples[i].accelMagG;
      if (g > maxAccelG) maxAccelG = g;
    }

    // Apogee + max altitude. Always recomputed from raw pressure against the
    // canonical ground reference (FlightData.groundRawPress — the averaged
    // pre-launch reading), rather than trusting any altitude stored in an
    // older CSV export, so this stays consistent no matter the data source.
    int apogeeIdx = 0;
    final groundRawPress = data.groundRawPress;
    double best = double.negativeInfinity;
    for (int i = 0; i < samples.length; i++) {
      final alt = lps22hb.altitudeM(samples[i].rawPress, groundRawPress);
      if (alt > best) { best = alt; apogeeIdx = i; }
    }
    final maxAltM = best > 0 ? best : 0.0;

    // Recovery: first window of 5 consecutive slow-phase samples within 1500 raw.
    int timeRecoveryMs = 0;
    const windowSize = 5;
    const pressureTol = 1500;
    final slowStart = fastEnd;
    if (samples.length >= slowStart + windowSize) {
      outer:
      for (int i = slowStart; i <= samples.length - windowSize; i++) {
        int lo = samples[i].rawPress;
        int hi = samples[i].rawPress;
        for (int j = i + 1; j < i + windowSize; j++) {
          final p = samples[j].rawPress;
          if (p < lo) lo = p;
          if (p > hi) hi = p;
          if (hi - lo > pressureTol) continue outer;
        }
        timeRecoveryMs = samples[i].timeMs;
        break;
      }
    }

    // Shift all reported times from firmware-t0-relative to true-ignition-
    // relative (see FlightData.ignitionOffsetMs). 0 is a "not detected"
    // sentinel for burnout/recovery only (see stats_widget.dart's _ms()) and
    // must be left alone rather than shifted into a false detected time;
    // flightTime/apogee are always real values, so shift unconditionally.
    final ignitionOffsetMs = data.ignitionOffsetMs;
    int shiftMs(int ms) => ms - ignitionOffsetMs;
    int shiftDetectedMs(int ms) => ms == 0 ? 0 : shiftMs(ms);

    return FlightStats(
      flightTimeMs: shiftMs(samples.last.timeMs),
      maxAccelMg: (maxAccelG * 1000).round(),
      minRawPress: samples[apogeeIdx].rawPress,
      timeBurnoutMs: shiftDetectedMs(timeBurnoutMs),
      timeApogeeMs: shiftMs(samples[apogeeIdx].timeMs),
      timeRecoveryMs: shiftDetectedMs(timeRecoveryMs),
      groundRawPress: groundRawPress,
      groundRawTemp: data.metadata.groundRawTemp,
      maxAltM: maxAltM,
      baroType: data.metadata.baroType,
      ignitionOffsetMs: ignitionOffsetMs,
    );
  }
}
