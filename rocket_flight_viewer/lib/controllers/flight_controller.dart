import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lps22hb.dart' as lps22hb;
import '../models/flight_sample.dart';
import '../models/comm_entry.dart';
import '../models/flight_data.dart';
import '../models/flight_stats.dart';
import '../models/live_sample.dart';
import '../services/base_serial_service.dart';
import '../services/serial_service.dart';
import '../services/android_serial_service.dart';
import '../services/payload_service.dart';

enum AppStatus { disconnected, connected, busy, error }

class FlightController extends ChangeNotifier {
  late final BaseSerialService _serial;
  late final _payload = PayloadService(_serial);

  final List<CommEntry> commLog = [];

  FlightController() {
    _serial = Platform.isAndroid ? AndroidSerialService() : SerialService();
    _serial.onLog = (isTx, bytes) {
      if (commLog.length >= 1000) commLog.removeAt(0);
      commLog.add(CommEntry(isTx: isTx, bytes: bytes));
      notifyListeners();
    };
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final tm = p.getString('themeMode') ?? 'dark';
    themeMode = tm == 'light' ? ThemeMode.light : tm == 'system' ? ThemeMode.system : ThemeMode.dark;
    useImperial = p.getBool('useImperial') ?? true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('themeMode', mode == ThemeMode.light ? 'light' : mode == ThemeMode.system ? 'system' : 'dark');
  }

  Future<void> setUnits(bool imperial) async {
    useImperial = imperial;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('useImperial', imperial);
  }

  AppStatus status = AppStatus.disconnected;
  String statusMessage = 'Not connected';
  String? selectedPort;
  FlightData? flightData;
  FlightStats? flightStats;
  FlightStats? _picStats; // PIC-reported stats from 'F' command, for CSV export only
  int? configThrMg;
  int? configLpfSetting;
  int? configFastMaxS;
  int? configOdrSel;
  int? configLaunchConfirmSamples;
  double downloadProgress = 0.0;

  int? productType;         // 2=STANDARD, 3=PRO; null=unknown
  int baroType = 1;         // 1=LPS22HB, 2=BMP581; defaults to LPS22HB until connected
  bool get hasStorage => productType == 2 || productType == 3;
  bool get isPro => productType == 3;

  // PRO only: flight directory (8 slots), refreshed on connect/erase/download.
  List<(bool, int)> flightSlots = []; // (valid, totalCount) per slot, index 0-7
  int? nextSlot;
  int selectedSlot = 0;

  int? batteryAdcCounts;
  // Vbat = counts × (3.3 / 1023) × 2 — VDD ref (XC6206 3.3V), 1MΩ/1MΩ divider → ~6.45mV/count
  double? get batteryVoltage => batteryAdcCounts != null
      ? batteryAdcCounts! * (3.3 / 1023.0) * 2.0
      : null;
  Timer? _batteryTimer;

  FlightData? historyData;
  FlightStats? historyStats;
  String? historyFileName;

  FlightData? historyData2;
  FlightStats? historyStats2;
  String? historyFileName2;

  // App settings — persisted via shared_preferences
  ThemeMode themeMode = ThemeMode.dark;
  bool useImperial = true;

  LiveSample? liveSample;
  final List<LivePoint> liveHistory = [];
  DateTime? _liveStartTime;
  bool liveActive = false;
  Timer? _liveTimer;
  bool _livePolling = false;

  bool get isConnected => status != AppStatus.disconnected;
  bool get isBusy => status == AppStatus.busy;
  bool get isError => status == AppStatus.error;
  List<String> get availablePorts => _serial.availablePorts;

  Future<void> refreshPorts() async {
    await _serial.refreshPorts();
    notifyListeners();
  }

  void selectPort(String? port) {
    selectedPort = port;
    notifyListeners();
  }

  void _onPortUnplugged() {
    _batteryTimer?.cancel();
    _batteryTimer = null;
    stopLive();
    _serial.onDisconnect = null;
    _serial.disconnect();
    status = AppStatus.disconnected;
    statusMessage = 'Payload unplugged';
    productType = null;
    baroType = 1;
    batteryAdcCounts = null;
    configThrMg = null;
    configLpfSetting = null;
    configFastMaxS = null;
    configOdrSel = null;
    configLaunchConfirmSamples = null;
    flightSlots = [];
    nextSlot = null;
    selectedSlot = 0;
    flightData = null;
    flightStats = null;
    _picStats = null;
    downloadProgress = 0.0;
    notifyListeners();
  }

  Future<void> connect() async {
    if (selectedPort == null) return;
    if (await _serial.connectAsync(selectedPort!)) {
      _serial.onDisconnect = _onPortUnplugged;
      // Clear all device-specific data so stale values never show on reconnect.
      configThrMg = null;
      configLpfSetting = null;
      configFastMaxS = null;
      configOdrSel = null;
      productType = null;
      baroType = 1;
      batteryAdcCounts = null;
      flightData = null;
      flightStats = null;
      _picStats = null;
      flightSlots = [];
      nextSlot = null;
      selectedSlot = 0;
      status = AppStatus.connected;
      statusMessage = 'Connected to $selectedPort';
      _fetchOnConnect();
    } else {
      statusMessage = 'Failed to open $selectedPort';
    }
    notifyListeners();
  }

  Future<void> _fetchOnConnect() async {
    await _fetchProductType();
    await _fetchConfigOnConnect();
    await _fetchBatteryVoltage();
    if (isPro) await fetchFlightDirectory();
    if (status != AppStatus.error) {
      statusMessage = 'Connected to $selectedPort — payload arming re-enabled';
      notifyListeners();
    }
    _scheduleBatteryPoll();
  }

  void _scheduleBatteryPoll() {
    _batteryTimer?.cancel();
    _batteryTimer = Timer(const Duration(seconds: 30), () => _pollBattery());
  }

  Future<void> _fetchProductType() async {
    final info = await _payload.getProductInfo();
    if (info != null && (info.$1 == 2 || info.$1 == 3)) {
      productType = info.$1;
      baroType = info.$2;
      notifyListeners();
    }
  }

  Future<void> _fetchConfigOnConnect() async {
    final val = await _payload.getConfig();
    if (val != null) {
      configThrMg = val.$1;
      configLpfSetting = val.$2;
      configFastMaxS = val.$3;
      configOdrSel = val.$4;
      configLaunchConfirmSamples = val.$5;
      notifyListeners();
    } else {
      _error('Read failed — device not responding');
    }
  }

  /// PRO only: refresh the 8-slot flight directory and pick a sensible
  /// default slot (the most recently recorded flight, if any).
  Future<void> fetchFlightDirectory() async {
    final dir = await _payload.getFlightDirectory();
    if (dir == null) return;
    final (next, slots) = dir;
    nextSlot = next;
    flightSlots = slots;
    final lastRecorded = (next - 1 + 8) % 8;
    selectedSlot = slots[lastRecorded].$1 ? lastRecorded : 0;
    notifyListeners();
  }

  Future<void> _fetchBatteryVoltage() async {
    final counts = await _payload.getBatteryVoltage();
    if (counts != null) {
      batteryAdcCounts = counts;
      notifyListeners();
    }
  }

  Future<void> _pollBattery() async {
    if (!isConnected || isBusy) return;
    final counts = await _payload.getBatteryVoltage();
    if (counts != null) {
      batteryAdcCounts = counts;
      notifyListeners();
    }
    if (isConnected) _scheduleBatteryPoll();
  }

  void disconnect() {
    _batteryTimer?.cancel();
    _batteryTimer = null;
    stopLive();
    _serial.onDisconnect = null;
    _serial.disconnect();
    status = AppStatus.disconnected;
    statusMessage = 'Disconnected';
    productType = null;
    baroType = 1;
    batteryAdcCounts = null;
    configThrMg = null;
    configLpfSetting = null;
    configFastMaxS = null;
    configOdrSel = null;
    configLaunchConfirmSamples = null;
    flightSlots = [];
    nextSlot = null;
    selectedSlot = 0;
    flightData = null;
    flightStats = null;
    _picStats = null;
    downloadProgress = 0.0;
    notifyListeners();
  }

  void startLive() {
    liveActive = true;
    liveHistory.clear();
    _liveStartTime = DateTime.now();
    _pollLive();
    _liveTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _pollLive());
    notifyListeners();
  }

  void stopLive() {
    _liveTimer?.cancel();
    _liveTimer = null;
    liveActive = false;
    liveSample = null;
    liveHistory.clear();
    _liveStartTime = null;
    notifyListeners();
  }

  Future<void> _pollLive() async {
    if (!isConnected || isBusy || _livePolling) return;
    _livePolling = true;
    final sample = await _payload.getLiveSample();
    _livePolling = false;
    if (sample != null && liveActive) {
      liveSample = sample;
      final t = DateTime.now().difference(_liveStartTime!).inMilliseconds / 1000.0;
      liveHistory.add(LivePoint(timeSec: t, sample: sample));
      if (liveHistory.length > 60) liveHistory.removeAt(0);
      notifyListeners();
    }
  }

  void selectSlot(int slot) {
    if (selectedSlot == slot) return;
    selectedSlot = slot;
    notifyListeners();
  }

  Future<void> downloadFlight() async {
    _busy('Downloading flight data…');
    downloadProgress = 0.0;
    final data = await _payload.downloadFlight(
      slot: isPro ? selectedSlot : null,
      baroType: baroType,
      onProgress: (p) {
        downloadProgress = p;
        notifyListeners();
      },
    );
    if (data != null) {
      flightData = data;
      flightStats = FlightStats.fromData(data);
      _picStats = await _payload.getFlightStats();
      _done('Downloaded ${data.metadata.totalCount} samples');
    } else {
      _picStats = null;
      _error('Download failed — check connection or no data recorded');
    }
  }

  Future<void> fetchConfig() async {
    _busy('Reading config…');
    final val = await _payload.getConfig();
    if (val != null) {
      configThrMg = val.$1;
      configLpfSetting = val.$2;
      configFastMaxS = val.$3;
      configOdrSel = val.$4;
      configLaunchConfirmSamples = val.$5;
      _done('Config loaded');
    } else {
      _error('Config read failed');
    }
  }

  Future<void> setConfig(int thrMg, int lpfSetting, int fastMaxS, int odrSel, int launchConfirmSamples) async {
    if (liveActive) stopLive();
    await Future.delayed(const Duration(milliseconds: 50));
    _busy('Saving config…');
    final ok = await _payload.setConfig(thrMg, lpfSetting, fastMaxS, odrSel, launchConfirmSamples);
    if (ok) {
      configThrMg = thrMg;
      configLpfSetting = lpfSetting;
      configFastMaxS = fastMaxS;
      configOdrSel = odrSel;
      configLaunchConfirmSamples = launchConfirmSamples;
      _done('Config saved');
    } else {
      _error('Config save failed');
    }
  }

  /// Remaining slow recording capacity in minutes assuming the fast phase runs
  /// to its configured maximum. Returns null if product type or config unknown.
  int? get slowCapacityMinutes {
    final pt = productType;
    final fmax = configFastMaxS;
    if (pt == null || fmax == null) return null;
    // Both variants use 64KB flight slots; PRO slots also carry a 32-byte header.
    final storageBytes = pt == 3 ? 65536 - 32 : 65536;
    const sampleBytes = 15;
    const preLaunchBytes = 25 * sampleBytes;   // 25 samples at 50 Hz pre-launch
    const fastHzTable = {0x02: 50.0, 0x03: 25.0, 0x04: 10.0};
    final fastHz = fastHzTable[configOdrSel ?? 0x02] ?? 50.0;
    final fastBytesMax = preLaunchBytes + (fmax * fastHz * sampleBytes).round();
    if (fastBytesMax >= storageBytes) return 0;
    final slowSamples = (storageBytes - fastBytesMax) ~/ sampleBytes;
    return slowSamples ~/ 60;
  }

  String get defaultExportFileName {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return 'flight_$stamp.csv';
  }

  Future<void> exportCsv(String fileName) async {
    final data = flightData;
    if (data == null || data.isEmpty) return;

    // Android export is near-instant (write to temp + share sheet); skip the
    // busy state so the tree doesn't swap to the spinner and back mid-animation.
    if (!Platform.isAndroid) _busy('Preparing CSV…');

    final groundRawPress = data.groundRawPress;

    final sb = StringBuffer();
    sb.writeln('# format_version=1');
    if (data.metadata.slotIndex != null) {
      sb.writeln('# flight_slot=${data.metadata.slotIndex! + 1}');
    }
    sb.writeln('# fast_period_ms=${data.metadata.fastPeriodMs}  slow_period_ms=${data.metadata.slowPeriodMs}  pre_launch_count=${data.metadata.preLaunchCount}  fast_count=${data.metadata.fastCount}  total_count=${data.metadata.totalCount}');
    sb.writeln('# baro_type=${data.metadata.baroType}');
    if (data.metadata.groundRawPress != 0) {
      sb.writeln('# ground_raw_press=${data.metadata.groundRawPress}  ground_raw_temp=${data.metadata.groundRawTemp}');
    }
    // The actual zero reference altitude_m below is computed against —
    // averaged + motion-filtered pre-launch samples, see
    // FlightData.groundRawPress. Written so a spreadsheet can reproduce the
    // altitude_m column exactly, without redoing that averaging/filtering.
    sb.writeln('# launch_raw_press=$groundRawPress');
    // Marks the app's estimate of true ignition, in ms relative to t=0 above
    // (t=0 is the firmware's launch-confirm instant, which lags real ignition
    // — see FlightData.ignitionOffsetMs). Informational only: time_s in the
    // rows below is NOT shifted by this value, so the app can always
    // recompute the estimate fresh from the raw pre-launch samples rather
    // than trusting a stored one. Stats/chart displays subtract this from
    // time_s to align on true ignition.
    sb.writeln('# ignition_offset_ms=${data.ignitionOffsetMs}');
    final pic = _picStats;
    if (pic != null) {
      // Apply ODR correction to fast-phase apogee time; landing is slow-phase (timer-driven) so no correction needed.
      final nomMs = data.metadata.fastPeriodMs.toDouble();
      final actMs = data.metadata.actualFastPeriodMs > 0 ? data.metadata.actualFastPeriodMs : nomMs;
      final correctedApogeeMs = (pic.timeApogeeMs * actMs / nomMs).round();
      sb.writeln('# pic_apogee_ms=$correctedApogeeMs  pic_landing_ms=${pic.timeRecoveryMs}');
    }
    sb.writeln('time_s,raw_press,altitude_m,accel_x_mg,accel_y_mg,accel_z_mg,accel_mag_g,gyro_x_dps,gyro_y_dps,gyro_z_dps');

    for (final s in data.samples) {
      final altM = lps22hb.altitudeM(s.rawPress, groundRawPress).toStringAsFixed(2);
      final gx = (s.gyroX * FlightSample.gyroScaleDps).toStringAsFixed(2);
      final gy = (s.gyroY * FlightSample.gyroScaleDps).toStringAsFixed(2);
      final gz = (s.gyroZ * FlightSample.gyroScaleDps).toStringAsFixed(2);
      sb.writeln('${s.timeSec.toStringAsFixed(3)},${s.rawPress},$altM,${s.accelX},${s.accelY},${s.accelZ},${s.accelMagG.toStringAsFixed(4)},$gx,$gy,$gz');
    }

    if (Platform.isAndroid) {
      try {
        final bytes = Uint8List.fromList(utf8.encode(sb.toString()));
        final baseName = fileName.endsWith('.csv')
            ? fileName.substring(0, fileName.length - 4)
            : fileName;
        final path = await FileSaver.instance.saveAs(
            name: baseName, bytes: bytes, fileExtension: 'csv',
            mimeType: MimeType.csv);
        if (path != null) {
          _done('CSV saved');
        } else {
          _done('Export cancelled');
        }
      } catch (e) {
        _error('Save failed: $e');
      }
    } else {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save flight data',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (path != null) {
        await File(path).writeAsString(sb.toString());
        _done('CSV saved');
      } else {
        _done('Export cancelled');
      }
    }
  }

  (FlightData, FlightStats, String, bool) _parseCsvContent(String content, String fileName) {
    final lines = const LineSplitter().convert(content);
    int fastPeriodMs = 20, slowPeriodMs = 1000, preLaunchCount = 0, fastCount = 0, totalCount = 0;
    int groundRawPress = 0, groundRawTemp = 0, baroType = 1;
    bool hasVersion = false;

    for (final line in lines) {
      if (!line.startsWith('#')) break;
      if (line.contains('format_version=')) hasVersion = true;
      final m1 = RegExp(r'fast_period_ms=(\d+)').firstMatch(line);
      final m2 = RegExp(r'slow_period_ms=(\d+)').firstMatch(line);
      final m3 = RegExp(r'pre_launch_count=(\d+)').firstMatch(line);
      final m4 = RegExp(r'fast_count=(\d+)').firstMatch(line);
      final m5 = RegExp(r'total_count=(\d+)').firstMatch(line);
      final m6 = RegExp(r'ground_raw_press=(\d+)').firstMatch(line);
      final m7 = RegExp(r'ground_raw_temp=(\d+)').firstMatch(line);
      final m8 = RegExp(r'baro_type=(\d+)').firstMatch(line);
      if (m1 != null) fastPeriodMs = int.parse(m1.group(1)!);
      if (m2 != null) slowPeriodMs = int.parse(m2.group(1)!);
      if (m3 != null) preLaunchCount = int.parse(m3.group(1)!);
      if (m4 != null) fastCount = int.parse(m4.group(1)!);
      if (m5 != null) totalCount = int.parse(m5.group(1)!);
      if (m6 != null) groundRawPress = int.parse(m6.group(1)!);
      if (m7 != null) groundRawTemp = int.parse(m7.group(1)!);
      if (m8 != null) baroType = int.parse(m8.group(1)!);
    }

    final headerIdx = lines.indexWhere((l) => l.startsWith('time_s'));
    if (headerIdx < 0) throw 'Invalid CSV — missing header row';

    final samples = <FlightSample>[];
    for (int i = headerIdx + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final p = line.split(',');
      if (p.length < 10) continue;
      final gyroX = (double.parse(p[7]) / FlightSample.gyroScaleDps).round();
      final gyroY = (double.parse(p[8]) / FlightSample.gyroScaleDps).round();
      final gyroZ = (double.parse(p[9]) / FlightSample.gyroScaleDps).round();
      samples.add(FlightSample(
        timeMs: (double.parse(p[0]) * 1000).round(),
        rawPress: int.parse(p[1]),
        altitudeM: p[2].isEmpty ? null : double.tryParse(p[2]),
        accelX: int.parse(p[3]),
        accelY: int.parse(p[4]),
        accelZ: int.parse(p[5]),
        gyroX: gyroX,
        gyroY: gyroY,
        gyroZ: gyroZ,
      ));
    }

    if (samples.isEmpty) throw 'CSV contains no valid samples';

    final data = FlightData(
      metadata: FlightMetadata(
        fastPeriodMs: fastPeriodMs,
        slowPeriodMs: slowPeriodMs,
        preLaunchCount: preLaunchCount,
        fastCount: fastCount,
        totalCount: totalCount != 0 ? totalCount : samples.length,
        groundRawPress: groundRawPress,
        groundRawTemp: groundRawTemp,
        baroType: baroType,
      ),
      samples: samples,
    );
    final stats = FlightStats.fromData(data);
    return (data, stats, fileName, !hasVersion);
  }

  /// Opens a platform-appropriate file picker and returns (csvContent, fileName),
  /// or (null, null) if cancelled. On Android uses FileType.any so cloud storage
  /// providers (Google Drive, OneDrive, Dropbox) appear in the system picker.
  Future<(String?, String?)> _pickCsvFile(String dialogTitle) async {
    if (Platform.isAndroid) {
      final result = await FilePicker.pickFiles(
        dialogTitle: dialogTitle,
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return (null, null);
      final f = result.files.first;
      if (!f.name.toLowerCase().endsWith('.csv')) {
        _error('Please select a .csv file');
        return (null, null);
      }
      final bytes = f.bytes;
      if (bytes == null) { _error('Cannot read file'); return (null, null); }
      return (utf8.decode(bytes), f.name);
    } else {
      final result = await FilePicker.pickFiles(
        dialogTitle: dialogTitle,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result == null || result.files.isEmpty) return (null, null);
      final path = result.files.first.path;
      if (path == null) { _error('Cannot read file'); return (null, null); }
      return (await File(path).readAsString(), path.split(RegExp(r'[/\\]')).last);
    }
  }

  Future<void> importCsv([BuildContext? ctx]) async {
    final (content, name) = await _pickCsvFile('Open flight CSV');
    if (content == null) return;
    final savedStatus = status;
    final savedMsg = statusMessage;
    _busy('Loading CSV…');
    try {
      final (data, stats, fileName, isOldFormat) = _parseCsvContent(content, name!);
      historyData = data;
      historyStats = stats;
      historyFileName = fileName;
      historyData2 = null;
      historyStats2 = null;
      historyFileName2 = null;
      status = savedStatus;
      statusMessage = 'Loaded ${data.samples.length} samples from CSV';
      notifyListeners();
      if (isOldFormat && ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Warning: Attempting to Upload Older File Format!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ));
      }
    } catch (e) {
      status = savedStatus;
      statusMessage = savedMsg;
      notifyListeners();
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('CSV parse error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ));
      }
    }
  }

  Future<void> importCsvCompare([BuildContext? ctx]) async {
    final (content, name) = await _pickCsvFile('Open comparison flight CSV');
    if (content == null) return;
    final savedStatus = status;
    final savedMsg = statusMessage;
    _busy('Loading comparison CSV…');
    try {
      final (data, stats, fileName, isOldFormat) = _parseCsvContent(content, name!);
      historyData2 = data;
      historyStats2 = stats;
      historyFileName2 = fileName;
      status = savedStatus;
      statusMessage = 'Loaded ${data.samples.length} comparison samples';
      notifyListeners();
      if (isOldFormat && ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Warning: Attempting to Upload Older File Format!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ));
      }
    } catch (e) {
      status = savedStatus;
      statusMessage = savedMsg;
      notifyListeners();
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('CSV parse error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ));
      }
    }
  }

  void clearHistoryCompare() {
    historyData2 = null;
    historyStats2 = null;
    historyFileName2 = null;
    notifyListeners();
  }

  Future<void> eraseStorage() async {
    _busy('Erasing storage…');
    final ok = await _payload.eraseStorage();
    if (ok) {
      flightData = null;
      if (isPro) await fetchFlightDirectory();
      _done('Storage erased');
    } else {
      _error('Erase failed');
    }
  }

  void _busy(String msg) {
    status = AppStatus.busy;
    statusMessage = msg;
    notifyListeners();
  }

  void clearLog() {
    commLog.clear();
    notifyListeners();
  }

  void _done(String msg) {
    status = AppStatus.connected;
    statusMessage = msg;
    notifyListeners();
  }

  void _error(String msg) {
    status = AppStatus.error;
    statusMessage = msg;
    notifyListeners();
  }
}
