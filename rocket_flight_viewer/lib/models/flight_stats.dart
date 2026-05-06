import 'dart:math';
import 'bmp384_calib.dart';
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
  final double? maxAltM;      // max altitude above ground; null if calib unavailable

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
  });

  factory FlightStats.fromData(FlightData data, {Bmp384Calib? calib}) {
    final samples = data.samples;
    if (samples.isEmpty) {
      return FlightStats(
        flightTimeMs: 0, maxAccelMg: 0, minRawPress: 0,
        timeBurnoutMs: 0, timeApogeeMs: 0, timeRecoveryMs: 0,
        groundRawPress: data.metadata.groundRawPress,
        groundRawTemp: data.metadata.groundRawTemp,
      );
    }

    // Max accel magnitude — index tracked for burnout search start point
    double maxAccelG = 0;
    int maxAccelIdx = 0;
    for (int i = 0; i < samples.length; i++) {
      final g = samples[i].accelMagG;
      if (g > maxAccelG) { maxAccelG = g; maxAccelIdx = i; }
    }

    // Apogee + max altitude.
    // Priority: (1) altitude embedded in samples (from CSV export), (2) computed
    // from calib (live download from the matching device), (3) min raw pressure.
    int apogeeIdx = 0;
    double? maxAltM;
    if (samples.first.altitudeM != null) {
      // CSV path: altitude already stored per-sample, use it directly.
      double best = double.negativeInfinity;
      for (int i = 0; i < samples.length; i++) {
        final alt = samples[i].altitudeM!;
        if (alt > best) { best = alt; apogeeIdx = i; }
      }
      maxAltM = best > 0 ? best : 0;
    } else if (calib != null) {
      // Live download path: compute altitude from calibration.
      final groundRawTemp = data.metadata.groundRawTemp != 0
          ? data.metadata.groundRawTemp
          : samples.first.rawTemp;
      final groundTLin = calib.tLin(groundRawTemp);
      final groundPa = calib.pressurePa(data.groundRawPress, groundTLin);
      final groundAltM = Bmp384Calib.altitudeM(groundPa);
      double best = double.negativeInfinity;
      for (int i = 0; i < samples.length; i++) {
        final pa = calib.pressurePa(samples[i].rawPress, calib.tLin(samples[i].rawTemp));
        final alt = Bmp384Calib.altitudeM(pa) - groundAltM;
        if (alt > best) { best = alt; apogeeIdx = i; }
      }
      maxAltM = best > 0 ? best : 0;
    } else {
      // Fallback: minimum raw pressure as proxy for apogee.
      int minPress = samples.first.rawPress;
      for (int i = 0; i < samples.length; i++) {
        if (samples[i].rawPress < minPress) {
          minPress = samples[i].rawPress;
          apogeeIdx = i;
        }
      }
    }

    // Burnout: first run of 3 consecutive fast-phase samples where accel has
    // dropped back toward 1g after the thrust peak. Threshold of 1300 mg sits
    // above resting gravity (1000 mg) but below any meaningful powered phase,
    // so it fires at the end of a motor burn or a hand-throw alike.
    // Slow-phase samples (1 Hz) are too coarse for reliable detection.
    // Burnout: first high→low crossing of 1300 mg in the fast phase.
    // Don't anchor to global max — a later spike (spin, landing) could shift
    // the search window past the real burnout event.
    int timeBurnoutMs = 0;
    const burnoutThreshMg = 1300;
    final fastEnd = min(data.metadata.fastCount, samples.length);
    bool seenPowered = false;
    for (int i = 0; i < fastEnd; i++) {
      final mg = (samples[i].accelMagG * 1000).round();
      if (!seenPowered) {
        if (mg >= burnoutThreshMg) seenPowered = true;
      } else if (mg < burnoutThreshMg) {
        timeBurnoutMs = samples[i].timeMs;
        break;
      }
    }

    // Recovery: first window of 5 consecutive slow-phase samples within 1500 raw.
    int timeRecoveryMs = 0;
    const windowSize = 5;
    const pressureTol = 1500;
    final slowStart = min(data.metadata.fastCount, samples.length);
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

    return FlightStats(
      flightTimeMs: samples.last.timeMs,
      maxAccelMg: (maxAccelG * 1000).round(),
      minRawPress: samples[apogeeIdx].rawPress,
      timeBurnoutMs: timeBurnoutMs,
      timeApogeeMs: samples[apogeeIdx].timeMs,
      timeRecoveryMs: timeRecoveryMs,
      groundRawPress: data.metadata.groundRawPress,
      groundRawTemp: data.metadata.groundRawTemp,
      maxAltM: maxAltM,
    );
  }
}
