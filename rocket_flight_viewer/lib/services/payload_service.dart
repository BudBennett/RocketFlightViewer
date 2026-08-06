import '../models/flight_data.dart';
import '../models/flight_sample.dart';
import '../models/flight_stats.dart';
import '../models/live_sample.dart';
import 'base_serial_service.dart';

class PayloadService {
  final BaseSerialService _serial;

  PayloadService(this._serial);

  // Returns (thrMg, lpfSetting, fastPhaseMaxS, odrSel, launchConfirmSamples) or null on failure.
  Future<(int, int, int, int, int)?> getConfig() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x43])) return null; // 'C'
    final data = await _serial.readBytes(6, timeoutMs: 2000);
    if (data == null) return null;
    return ((data[0] << 8) | data[1], data[2], data[3], data[4], data[5]); // thrMg, lpf, fastMaxS, odrSel, launchConfirm
  }

  Future<bool> setConfig(int thrMg, int lpfSetting, int fastPhaseMaxS, int odrSel, int launchConfirmSamples) async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x53, (thrMg >> 8) & 0xFF, thrMg & 0xFF, lpfSetting & 0xFF, fastPhaseMaxS & 0xFF, odrSel & 0xFF, launchConfirmSamples & 0xFF])) return false; // 'S'
    final data = await _serial.readBytes(1, timeoutMs: 2000);
    return data != null && data[0] == 0x41; // 'A'
  }

  Future<bool> eraseStorage() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x45])) return false; // 'E'
    final data = await _serial.readBytes(1, timeoutMs: 5000);
    return data != null && data[0] == 0x41; // 'A'
  }

  Future<FlightStats?> getFlightStats() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x46])) return null; // 'F'
    // 24 bytes: flight_time_ms(3) max_accel_mg(2) min_raw_press(4)
    //           time_burnout_ms(3) time_apogee_ms(3) time_recovery_ms(3)
    //           ground_raw_press(3) ground_raw_temp(3)
    final data = await _serial.readBytes(24, timeoutMs: 2000);
    if (data == null) return null;

    var offset = 0;

    int readU24() {
      final v = data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16);
      offset += 3;
      return v;
    }

    int readU16() {
      final v = data[offset] | (data[offset + 1] << 8);
      offset += 2;
      return v;
    }

    int readU32() {
      final v = data[offset] |
          (data[offset + 1] << 8) |
          (data[offset + 2] << 16) |
          (data[offset + 3] << 24);
      offset += 4;
      return v;
    }

    return FlightStats(
      flightTimeMs:   readU24(),
      maxAccelMg:     readU16(),
      minRawPress:    readU32(),
      timeBurnoutMs:  readU24(),
      timeApogeeMs:   readU24(),
      timeRecoveryMs: readU24(),
      groundRawPress: readU24(),
      groundRawTemp:  readU24(),
    );
  }

  // PRO only: flight directory query. Returns (nextSlot, slots) where slots
  // is a list of 8 (valid, totalCount) entries, or null on failure.
  Future<(int, List<(bool, int)>)?> getFlightDirectory() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x47])) return null; // 'G'
    // 1 + 8 * (valid(1) + total_count(uint16 LE))
    final data = await _serial.readBytes(25, timeoutMs: 2000);
    if (data == null) return null;
    final nextSlot = data[0];
    final slots = <(bool, int)>[];
    for (var i = 0; i < 8; i++) {
      final off = 1 + i * 3;
      final valid = data[off] != 0;
      final total = data[off + 1] | (data[off + 2] << 8);
      slots.add((valid, total));
    }
    return (nextSlot, slots);
  }

  // [slot] selects the flight slot for PRO (0-7); pass null for STANDARD.
  // [baroType] (1=LPS22HB, 2=BMP581) is the sensor fitted to the connected
  // device, fetched separately via getProductInfo() — stamped onto the
  // returned metadata so altitude scaling stays correct after download.
  Future<FlightData?> downloadFlight({int? slot, int baroType = 1, void Function(double progress)? onProgress}) async {
    _serial.flushRx();
    final cmd = slot != null ? [0x44, slot & 0xFF] : [0x44]; // 'D'
    if (!_serial.sendBytes(cmd)) return null;

    // 22-byte metadata: uint16 x4 + uint24 x2 + uint16 + uint32 + uint16 (all LE)
    //   fast_period_ms, slow_period_ms, fast_count, total_count (uint16 each)
    //   ground_raw_press, ground_raw_temp (uint24 each)
    //   calib_drdy_count (uint16), calib_elapsed_ticks (uint32)
    //   pre_launch_count (uint16)
    final meta = await _serial.readBytes(22, timeoutMs: 3000);
    if (meta == null) return null;

    final fastPeriodMs        = meta[0]  | (meta[1]  << 8);
    final slowPeriodMs        = meta[2]  | (meta[3]  << 8);
    final fastCount           = meta[4]  | (meta[5]  << 8);
    final totalCount          = meta[6]  | (meta[7]  << 8);
    final groundRawPress      = meta[8]  | (meta[9]  << 8) | (meta[10] << 16);
    final groundRawTemp       = meta[11] | (meta[12] << 8) | (meta[13] << 16);
    final calibDrdyCount      = meta[14] | (meta[15] << 8);
    final calibElapsedTicks   = meta[16] | (meta[17] << 8) | (meta[18] << 16) | (meta[19] << 24);
    final preLaunchCount      = meta[20] | (meta[21] << 8);

    // Timer0 tick = 256 × (1 / (8MHz/4/8)) = 1.024 ms.
    // Calibration is measured while the baro runs at 50 Hz during arming, so it
    // correctly corrects the fast-phase ODR only when the configured rate is 50 Hz
    // (fastPeriodMs == 20).  At slower configured rates, use the nominal period.
    const timer0PeriodMs = 1.024;
    final actualFastPeriodMs = (calibDrdyCount > 0 && fastPeriodMs == 20)
        ? (calibElapsedTicks * timer0PeriodMs) / calibDrdyCount
        : fastPeriodMs.toDouble();

    final metadata = FlightMetadata(
      fastPeriodMs: fastPeriodMs,
      slowPeriodMs: slowPeriodMs,
      fastCount: fastCount,
      totalCount: totalCount,
      preLaunchCount: preLaunchCount,
      groundRawPress: groundRawPress,
      groundRawTemp: groundRawTemp,
      actualFastPeriodMs: actualFastPeriodMs,
      slotIndex: slot,
      baroType: baroType,
    );

    if (totalCount == 0) {
      return FlightData(metadata: metadata, samples: []);
    }

    // At 76800 baud (~7680 B/s): budget 2× theoretical time + 10s overhead.
    final totalBytes = totalCount * 15;
    final timeoutMs = (totalBytes * 2 + 10000).clamp(10000, 300000);

    final raw = await _serial.readBytes(totalBytes, timeoutMs: timeoutMs);
    if (raw == null) return null;

    final samples = <FlightSample>[];
    for (var i = 0; i < totalCount; i++) {
      final b = i * 15;
      final rawPress = raw[b] | (raw[b + 1] << 8) | (raw[b + 2] << 16);
      final ax = _s16(raw[b + 3] | (raw[b + 4] << 8));
      final ay = _s16(raw[b + 5] | (raw[b + 6] << 8));
      final az = _s16(raw[b + 7] | (raw[b + 8] << 8));
      final gx = _s16(raw[b + 9] | (raw[b + 10] << 8));
      final gy = _s16(raw[b + 11] | (raw[b + 12] << 8));
      final gz = _s16(raw[b + 13] | (raw[b + 14] << 8));

      final int timeMs;
      if (i < preLaunchCount) {
        // Pre-launch: always 20ms period, t=0 is launch detect
        timeMs = (i - preLaunchCount) * 20;
      } else {
        final fi = i - preLaunchCount;   // index within fast+slow region
        timeMs = fi < fastCount
            ? (fi * actualFastPeriodMs).round()
            : (fastCount * actualFastPeriodMs).round() + (fi - fastCount) * slowPeriodMs;
      }

      samples.add(FlightSample(
        timeMs: timeMs,
        rawPress: rawPress,
        accelX: ax,
        accelY: ay,
        accelZ: az,
        gyroX: gx,
        gyroY: gy,
        gyroZ: gz,
      ));

      if (onProgress != null && i % 100 == 0) {
        onProgress(i / totalCount);
      }
    }

    return FlightData(metadata: metadata, samples: samples);
  }

  // Lower nibble: productType (2=STANDARD, 3=PRO). Upper nibble: baroType
  // (1=LPS22HB, 2=BMP581) — 0 on firmware predating BMP581 support, which
  // only ever shipped with LPS22HB, so the caller should treat 0 as LPS22HB.
  Future<(int, int)?> getProductInfo() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x49])) return null; // 'I'
    final data = await _serial.readBytes(1, timeoutMs: 2000);
    if (data == null) return null;
    final productType = data[0] & 0x0F;
    final baroType = (data[0] >> 4) == 0 ? 1 : (data[0] >> 4);
    return (productType, baroType);
  }

  Future<int?> getBatteryVoltage() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x42])) return null; // 'B'
    final data = await _serial.readBytes(2, timeoutMs: 2000);
    if (data == null) return null;
    return data[0] | (data[1] << 8); // 10-bit ADC counts, little-endian
  }

  // Puts the PIC to sleep (~22µA) while USB stays connected for charging.
  // The firmware acks with 'A' before sleeping, then goes silent — it will
  // not respond to anything else until it wakes on a hall-effect edge (arm
  // gesture) or on the next command sent after a normal reconnect. Callers
  // must not treat that silence as a disconnect/error.
  Future<bool> sleepForCharging() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x5A])) return false; // 'Z'
    final data = await _serial.readBytes(1, timeoutMs: 2000);
    return data != null && data[0] == 0x41; // 'A'
  }

  Future<LiveSample?> getLiveSample() async {
    _serial.flushRx();
    if (!_serial.sendBytes([0x4C])) return null; // 'L'
    // Firmware sends 15 bytes: pressure(3) + accel(6) + gyro(6), all LE.
    final data = await _serial.readBytes(15, timeoutMs: 300);
    if (data == null) return null;
    return LiveSample(
      rawPress: data[0] | (data[1] << 8) | (data[2] << 16),
      accelX:  _s16(data[3]  | (data[4]  << 8)),
      accelY:  _s16(data[5]  | (data[6]  << 8)),
      accelZ:  _s16(data[7]  | (data[8]  << 8)),
      gyroX:   _s16(data[9]  | (data[10] << 8)),
      gyroY:   _s16(data[11] | (data[12] << 8)),
      gyroZ:   _s16(data[13] | (data[14] << 8)),
    );
  }

  static int _s16(int v) => v >= 0x8000 ? v - 0x10000 : v;
}
