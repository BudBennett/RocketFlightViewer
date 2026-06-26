import 'dart:io';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/lps22hb.dart' as lps22hb;
import '../models/live_sample.dart';
import '../utils/theme_utils.dart';

const double _kWindowSec = 10.0;
const double _kChartHeight = 180.0;

class LiveWidget extends StatefulWidget {
  final LiveSample? sample;
  final List<LivePoint> history;
  final bool useImperial;
  final int baroType; // 1=LPS22HB, 2=BMP581

  const LiveWidget({
    super.key,
    required this.sample,
    required this.history,
    this.useImperial = true,
    this.baroType = 1,
  });

  @override
  State<LiveWidget> createState() => _LiveWidgetState();
}

class _LiveWidgetState extends State<LiveWidget> {
  bool _baroChart = false;
  bool _accelChart = false;
  bool _gyroChart = false;
  bool _paused = false;
  List<LivePoint> _frozenHistory = [];

  void _togglePause() {
    setState(() {
      if (_paused) {
        _paused = false;
        _frozenHistory = [];
      } else {
        _frozenHistory = List.from(widget.history);
        _paused = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sample == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final s = widget.sample!;
    final altitudeValue = widget.useImperial
        ? '${lps22hb.altitudeMslFt(s.rawPress, widget.baroType).toStringAsFixed(1)} ft'
        : '${lps22hb.altitudeMslM(s.rawPress, widget.baroType).toStringAsFixed(1)} m';
    final pressureValue = '${lps22hb.pressureHPa(s.rawPress, widget.baroType).toStringAsFixed(2)} hPa';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionCard(
            title: 'Barometer',
            showChart: _baroChart,
            onToggleChart: () => setState(() => _baroChart = !_baroChart),
            isPaused: _paused,
            onTogglePause: _togglePause,
            chart: _MiniChart(
              history: _paused ? _frozenHistory : widget.history,
              type: _ChartType.baro,
              useImperial: widget.useImperial,
              baroType: widget.baroType,
            ),
            children: [
              _DataRow(label: 'Altitude (MSL)', value: altitudeValue),
              _DataRow(label: 'Pressure', value: pressureValue),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Accelerometer',
            showChart: _accelChart,
            onToggleChart: () => setState(() => _accelChart = !_accelChart),
            isPaused: _paused,
            onTogglePause: _togglePause,
            chart: _MiniChart(
              history: _paused ? _frozenHistory : widget.history,
              type: _ChartType.accel,
            ),
            children: [
              _AxisRow(axis: 'X', value: s.accelXg, unit: 'g'),
              _AxisRow(axis: 'Y', value: s.accelYg, unit: 'g'),
              _AxisRow(axis: 'Z', value: s.accelZg, unit: 'g'),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Gyroscope',
            showChart: _gyroChart,
            onToggleChart: () => setState(() => _gyroChart = !_gyroChart),
            isPaused: _paused,
            onTogglePause: _togglePause,
            chart: _MiniChart(
              history: _paused ? _frozenHistory : widget.history,
              type: _ChartType.gyro,
            ),
            children: [
              _AxisRow(axis: 'X', value: s.gyroXdps, unit: 'dps'),
              _AxisRow(axis: 'Y', value: s.gyroYdps, unit: 'dps'),
              _AxisRow(axis: 'Z', value: s.gyroZdps, unit: 'dps'),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section card with optional chart toggle
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool showChart;
  final VoidCallback onToggleChart;
  final Widget chart;
  final bool isPaused;
  final VoidCallback? onTogglePause;

  const _SectionCard({
    required this.title,
    required this.children,
    required this.showChart,
    required this.onToggleChart,
    required this.chart,
    this.isPaused = false,
    this.onTogglePause,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (!Platform.isAndroid) ...[
                  if (showChart)
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 16,
                        icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                        tooltip: isPaused ? 'Resume' : 'Pause',
                        onPressed: onTogglePause,
                      ),
                    ),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      icon: Icon(showChart ? Icons.format_list_numbered : Icons.show_chart),
                      tooltip: showChart ? 'Show values' : 'Show chart',
                      onPressed: onToggleChart,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            if (showChart)
              SizedBox(height: _kChartHeight, child: chart)
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini strip chart
// ---------------------------------------------------------------------------

enum _ChartType { baro, accel, gyro }

class _MiniChart extends StatelessWidget {
  final List<LivePoint> history;
  final _ChartType type;
  final bool useImperial;
  final int baroType;

  const _MiniChart({
    required this.history,
    required this.type,
    this.useImperial = true,
    this.baroType = 1,
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Center(
        child: Text('Waiting for data…',
            style: TextStyle(fontSize: 12, color: secondaryTextColor(context))),
      );
    }

    final rawBars = _buildBars();
    final offset = -history.last.timeSec;
    final bars = _shiftBars(rawBars, offset);
    const double viewMinX = -_kWindowSec;
    const double viewMaxX = 0.0;

    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    for (final bar in bars) {
      for (final spot in bar.spots) {
        if (spot.x >= viewMinX) {
          if (spot.y < minY) minY = spot.y;
          if (spot.y > maxY) maxY = spot.y;
        }
      }
    }
    if (!minY.isFinite) minY = 0;
    if (!maxY.isFinite) maxY = 1;

    final yRange = math.max(0.5, maxY - minY);
    final yPad = yRange * 0.1;

    return LineChart(
      LineChartData(
        minX: viewMinX,
        maxX: viewMaxX,
        minY: minY - yPad,
        maxY: maxY + yPad,
        clipData: const FlClipData.all(),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: true),
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              getTitlesWidget: (v, _) =>
                  Text('${v.toInt()}s', style: const TextStyle(fontSize: 9)),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, _) => Text(
                v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1),
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ),
        ),
        lineBarsData: bars,
      ),
    );
  }

  List<LineChartBarData> _shiftBars(List<LineChartBarData> bars, double offset) =>
      bars.map((bar) => LineChartBarData(
            spots: bar.spots.map((s) => FlSpot(s.x + offset, s.y)).toList(),
            isCurved: bar.isCurved,
            color: bar.color,
            barWidth: bar.barWidth,
            dotData: bar.dotData,
            belowBarData: bar.belowBarData,
          )).toList();

  List<LineChartBarData> _buildBars() {
    switch (type) {
      case _ChartType.baro:
        return _baroBars();
      case _ChartType.accel:
        return _axisBars([
          (Colors.red, (LiveSample s) => s.accelXg),
          (Colors.green, (LiveSample s) => s.accelYg),
          (Colors.blue, (LiveSample s) => s.accelZg),
        ]);
      case _ChartType.gyro:
        return _axisBars([
          (Colors.red, (LiveSample s) => s.gyroXdps),
          (Colors.green, (LiveSample s) => s.gyroYdps),
          (Colors.blue, (LiveSample s) => s.gyroZdps),
        ]);
    }
  }

  List<LineChartBarData> _baroBars() {
    final spots = history
        .map((pt) => FlSpot(
              pt.timeSec,
              useImperial
                  ? lps22hb.altitudeMslFt(pt.sample.rawPress, baroType)
                  : lps22hb.altitudeMslM(pt.sample.rawPress, baroType),
            ))
        .toList();
    return [_bar(spots, Colors.blueAccent)];
  }

  List<LineChartBarData> _axisBars(
      List<(Color, double Function(LiveSample))> axes) {
    return axes.map((axis) {
      final spots =
          history.map((pt) => FlSpot(pt.timeSec, axis.$2(pt.sample))).toList();
      return _bar(spots, axis.$1);
    }).toList();
  }

  LineChartBarData _bar(List<FlSpot> spots, Color color) => LineChartBarData(
        spots: spots,
        isCurved: false,
        color: color,
        barWidth: 1.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );
}

// ---------------------------------------------------------------------------
// Value rows (unchanged)
// ---------------------------------------------------------------------------

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  const _DataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(color: secondaryTextColor(context), fontSize: 13)),
          ),
          Text(value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
        ],
      ),
    );
  }
}

class _AxisRow extends StatelessWidget {
  final String axis;
  final double value;
  final String unit;
  const _AxisRow({required this.axis, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    final formatted = '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text('  $axis',
                style: TextStyle(color: secondaryTextColor(context), fontSize: 13)),
          ),
          Text('$formatted $unit',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
        ],
      ),
    );
  }
}
