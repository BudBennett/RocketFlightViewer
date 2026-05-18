import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bmp384_calib.dart';
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
  double downloadProgress = 0.0;

  int? productType;         // 1=LITE, 2=STANDARD; null=unknown
  bool get hasStorage => productType == 2 || productType == 3;
  Bmp384Calib? calib;       // null until 'K' command succeeds

  FlightData? historyData;
  FlightStats? historyStats;
  Bmp384Calib? historyCalib;
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
    _serial.onDisconnect = null;
    _serial.disconnect();
    status = AppStatus.disconnected;
    statusMessage = 'Payload unplugged';
    productType = null;
    configThrMg = null;
    configLpfSetting = null;
    configFastMaxS = null;
    configOdrSel = null;
    calib = null;
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
      calib = null;
      flightStats = null;
      _picStats = null;
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
    await _fetchCalibration();
    if (status != AppStatus.error) {
      statusMessage = 'Connected to $selectedPort — payload arming re-enabled';
      notifyListeners();
    }
  }

  Future<void> _fetchProductType() async {
    final pt = await _payload.getProductType();
    if (pt != null) {
      productType = pt;
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
      notifyListeners();
    } else {
      _error('Read failed — device not responding');
    }
  }

  Future<void> _fetchCalibration() async {
    final c = await _payload.getCalibration();
    if (c != null) {
      calib = c;
      notifyListeners();
    }
  }

  void disconnect() {
    stopLive();
    _serial.onDisconnect = null;
    _serial.disconnect();
    status = AppStatus.disconnected;
    statusMessage = 'Disconnected';
    productType = null;
    configThrMg = null;
    configLpfSetting = null;
    configFastMaxS = null;
    configOdrSel = null;
    calib = null;
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

  Future<void> downloadFlight() async {
    _busy('Downloading flight data…');
    downloadProgress = 0.0;
    final data = await _payload.downloadFlight(onProgress: (p) {
      downloadProgress = p;
      notifyListeners();
    });
    if (data != null) {
      flightData = data;
      flightStats = FlightStats.fromData(data, calib: calib);
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
      _done('Config loaded');
    } else {
      _error('Config read failed');
    }
  }

  Future<void> setConfig(int thrMg, int lpfSetting, int fastMaxS, int odrSel) async {
    if (liveActive) stopLive();
    await Future.delayed(const Duration(milliseconds: 50));
    _busy('Saving config…');
    final ok = await _payload.setConfig(thrMg, lpfSetting, fastMaxS, odrSel);
    if (ok) {
      configThrMg = thrMg;
      configLpfSetting = lpfSetting;
      configFastMaxS = fastMaxS;
      configOdrSel = odrSel;
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
    final storageBytes = pt == 3 ? 131072 : 65536;
    const sampleBytes = 18;
    final fastHz = 50.0 / (1 << ((configOdrSel ?? 0x02) - 0x02));
    final fastBytesMax = (fmax * fastHz * sampleBytes).round();
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

    final c = calib;
    final sb = StringBuffer();
    sb.writeln('# format_version=1');
    sb.writeln('# fast_period_ms=${data.metadata.fastPeriodMs}  slow_period_ms=${data.metadata.slowPeriodMs}  fast_count=${data.metadata.fastCount}  total_count=${data.metadata.totalCount}');
    if (c != null) sb.writeln('# calib=${c.toLine()}');
    if (data.metadata.groundRawPress != 0) {
      sb.writeln('# ground_raw_press=${data.metadata.groundRawPress}  ground_raw_temp=${data.metadata.groundRawTemp}');
    }
    final pic = _picStats;
    if (pic != null) {
      // Apply ODR correction to fast-phase apogee time; landing is slow-phase (timer-driven) so no correction needed.
      final nomMs = data.metadata.fastPeriodMs.toDouble();
      final actMs = data.metadata.actualFastPeriodMs > 0 ? data.metadata.actualFastPeriodMs : nomMs;
      final correctedApogeeMs = (pic.timeApogeeMs * actMs / nomMs).round();
      sb.writeln('# pic_apogee_ms=$correctedApogeeMs  pic_landing_ms=${pic.timeRecoveryMs}');
    }
    sb.writeln('time_s,raw_press,raw_temp,altitude_m,accel_x_mg,accel_y_mg,accel_z_mg,accel_mag_g,gyro_x_dps,gyro_y_dps,gyro_z_dps');
    final groundRawTemp = data.metadata.groundRawTemp != 0
        ? data.metadata.groundRawTemp
        : (data.samples.isNotEmpty ? data.samples.first.rawTemp : 0);
    final groundTLin = (c != null && groundRawTemp != 0) ? c.tLin(groundRawTemp) : 25.0;
    final refAlt = c != null ? Bmp384Calib.altitudeM(c.pressurePa(data.groundRawPress, groundTLin)) : 0.0;

    for (final s in data.samples) {
      final tLin = c != null ? c.tLin(s.rawTemp) : 25.0;
      final altM = c != null
          ? (Bmp384Calib.altitudeM(c.pressurePa(s.rawPress, tLin)) - refAlt).toStringAsFixed(2)
          : '';
      final gx = (s.gyroX * FlightSample.gyroScaleDps).toStringAsFixed(2);
      final gy = (s.gyroY * FlightSample.gyroScaleDps).toStringAsFixed(2);
      final gz = (s.gyroZ * FlightSample.gyroScaleDps).toStringAsFixed(2);
      sb.writeln('${s.timeSec.toStringAsFixed(3)},${s.rawPress},${s.rawTemp},$altM,${s.accelX},${s.accelY},${s.accelZ},${s.accelMagG.toStringAsFixed(4)},$gx,$gy,$gz');
    }

    if (Platform.isAndroid) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(sb.toString());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Flight Data',
      );
      _done('CSV saved: $fileName');
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

  Future<(FlightData, Bmp384Calib?, FlightStats, String, bool)> _parseCsvPath(String path) async {
    final lines = await File(path).readAsLines();
    int fastPeriodMs = 20, slowPeriodMs = 1000, fastCount = 0, totalCount = 0;
    int groundRawPress = 0, groundRawTemp = 0;
    Bmp384Calib? parsedCalib;
    bool hasVersion = false;

    for (final line in lines) {
      if (!line.startsWith('#')) break;
      if (line.contains('format_version=')) hasVersion = true;
      final m1 = RegExp(r'fast_period_ms=(\d+)').firstMatch(line);
      final m2 = RegExp(r'slow_period_ms=(\d+)').firstMatch(line);
      final m3 = RegExp(r'fast_count=(\d+)').firstMatch(line);
      final m4 = RegExp(r'total_count=(\d+)').firstMatch(line);
      final m5 = RegExp(r'ground_raw_press=(\d+)').firstMatch(line);
      final m6 = RegExp(r'ground_raw_temp=(\d+)').firstMatch(line);
      if (m1 != null) fastPeriodMs = int.parse(m1.group(1)!);
      if (m2 != null) slowPeriodMs = int.parse(m2.group(1)!);
      if (m3 != null) fastCount = int.parse(m3.group(1)!);
      if (m4 != null) totalCount = int.parse(m4.group(1)!);
      if (m5 != null) groundRawPress = int.parse(m5.group(1)!);
      if (m6 != null) groundRawTemp = int.parse(m6.group(1)!);
      if (line.startsWith('# calib=')) {
        parsedCalib = Bmp384Calib.fromLine(line.substring('# calib='.length));
      }
    }

    final headerIdx = lines.indexWhere((l) => l.startsWith('time_s'));
    if (headerIdx < 0) throw 'Invalid CSV — missing header row';

    final samples = <FlightSample>[];
    for (int i = headerIdx + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final p = line.split(',');
      if (p.length < 11) continue;
      final gyroX = (double.parse(p[8]) / FlightSample.gyroScaleDps).round();
      final gyroY = (double.parse(p[9]) / FlightSample.gyroScaleDps).round();
      final gyroZ = (double.parse(p[10]) / FlightSample.gyroScaleDps).round();
      samples.add(FlightSample(
        timeMs: (double.parse(p[0]) * 1000).round(),
        rawPress: int.parse(p[1]),
        rawTemp: p[2].isEmpty ? 0 : int.parse(p[2]),
        altitudeM: p[3].isEmpty ? null : double.tryParse(p[3]),
        accelX: int.parse(p[4]),
        accelY: int.parse(p[5]),
        accelZ: int.parse(p[6]),
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
        fastCount: fastCount,
        totalCount: totalCount != 0 ? totalCount : samples.length,
        groundRawPress: groundRawPress,
        groundRawTemp: groundRawTemp,
      ),
      samples: samples,
    );
    final stats = FlightStats.fromData(data);
    final fileName = path.split(RegExp(r'[/\\]')).last;
    return (data, parsedCalib, stats, fileName, !hasVersion);
  }

  Future<void> importCsv([BuildContext? ctx]) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open flight CSV',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) { _error('Cannot read file'); return; }

    _busy('Loading CSV…');
    try {
      final (data, calib, stats, name, isOldFormat) = await _parseCsvPath(path);
      historyData = data;
      historyCalib = calib;
      historyStats = stats;
      historyFileName = name;
      // Clear comparison slot when the primary flight changes.
      historyData2 = null;
      historyStats2 = null;
      historyFileName2 = null;
      _done('Loaded ${data.samples.length} samples from CSV');
      if (isOldFormat && ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Warning: Attempting to Upload Older File Format!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ));
      }
    } catch (e) {
      _error('CSV parse error: $e');
    }
  }

  Future<void> importCsvCompare([BuildContext? ctx]) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open comparison flight CSV',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) { _error('Cannot read file'); return; }

    _busy('Loading comparison CSV…');
    try {
      final (data, calib, stats, name, isOldFormat) = await _parseCsvPath(path);
      historyData2 = data;
      historyStats2 = stats;
      historyFileName2 = name;
      _done('Loaded ${data.samples.length} comparison samples');
      if (isOldFormat && ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('Warning: Attempting to Upload Older File Format!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ));
      }
    } catch (e) {
      _error('CSV parse error: $e');
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
