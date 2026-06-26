import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/lps22hb.dart' as lps22hb;
import '../models/flight_data.dart';
import '../utils/theme_utils.dart';

class FlightChart extends StatefulWidget {
  final FlightData data;
  final bool useImperial;
  final FlightData? data2;
  final void Function(Color colorA, Color colorB)? onColorsChanged;

  const FlightChart({
    super.key,
    required this.data,
    this.useImperial = true,
    this.data2,
    this.onColorsChanged,
  });

  @override
  State<FlightChart> createState() => _FlightChartState();
}

class _FlightChartState extends State<FlightChart>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  static const _altColorA   = Colors.blue;
  static const _altColorB   = Colors.pinkAccent;
  static const _accelColorA = Colors.orange;
  static const _accelColorB = Colors.teal;

  Color get _colorA => _tabs.index == 0 ? _altColorA   : _accelColorA;
  Color get _colorB => _tabs.index == 0 ? _altColorB   : _accelColorB;

  // Zoom state — null means "use data range"
  double? _zoomMinX, _zoomMaxX;
  double? _zoomMinY, _zoomMaxY;

  // Rubber band selection state
  Offset? _selStart;
  Offset? _selCurrent;

  bool get _isZoomed =>
      _zoomMinX != null || _zoomMaxX != null ||
      _zoomMinY != null || _zoomMaxY != null;

  bool get _isComparing =>
      widget.data2 != null && !widget.data2!.isEmpty;

  void _resetZoom() => setState(() {
        _zoomMinX = _zoomMaxX = _zoomMinY = _zoomMaxY = null;
      });

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        _resetZoom();
        widget.onColorsChanged?.call(_colorA, _colorB);
      }
    });
  }

  @override
  void didUpdateWidget(FlightChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data2 != widget.data2) _resetZoom();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Altitude'), Tab(text: 'Acceleration')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildAltitudeChart(),
              _buildAccelChart(),
            ],
          ),
        ),
        if (!_isComparing) _buildSummaryRow(),
      ],
    );
  }

  Widget _buildAltitudeChart() {
    final samples = widget.data.samples;
    if (samples.isEmpty) return const Center(child: Text('No data'));

    final scale = widget.useImperial ? 3.28084 : 1.0;
    final unit  = widget.useImperial ? 'ft' : 'm';
    final label = 'Altitude above launch ($unit)';

    // Always recomputed from raw pressure against FlightData.groundRawPress
    // (the averaged, motion-filtered pre-launch reading) — never trust an
    // altitude column stored in an older CSV export, so this always agrees
    // with the Max Altitude stat for the same flight.
    final groundRawPress = widget.data.groundRawPress;
    final spotsA = samples.map((s) {
      final alt = lps22hb.altitudeM(s.rawPress, groundRawPress);
      return FlSpot(s.timeSec, alt * scale);
    }).toList();

    List<FlSpot> spotsB = const [];
    if (_isComparing) {
      final s2 = widget.data2!.samples;
      final groundRawPress2 = widget.data2!.groundRawPress;
      spotsB = s2.map((s) {
        final alt = lps22hb.altitudeM(s.rawPress, groundRawPress2);
        return FlSpot(s.timeSec, alt * scale);
      }).toList();
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: secondaryTextColor(context))),
          const SizedBox(height: 4),
          Expanded(
            child: _lineChart(
              spotsA, _altColorA, unit,
              spotsB: spotsB, colorB: _altColorB,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccelChart() {
    final samples = widget.data.samples;
    if (samples.isEmpty) return const Center(child: Text('No data'));

    final spotsA = samples.map((s) => FlSpot(s.timeSec, s.accelMagG)).toList();
    final spotsB = _isComparing
        ? widget.data2!.samples.map((s) => FlSpot(s.timeSec, s.accelMagG)).toList()
        : const <FlSpot>[];

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Acceleration magnitude (g)',
              style: TextStyle(fontSize: 11, color: secondaryTextColor(context))),
          const SizedBox(height: 4),
          Expanded(
            child: _lineChart(
              spotsA, _accelColorA, 'g',
              spotsB: spotsB, colorB: _accelColorB,
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineChart(
    List<FlSpot> spotsA,
    Color colorA,
    String yUnit, {
    List<FlSpot> spotsB = const [],
    Color colorB = Colors.red,
  }) {
    if (spotsA.isEmpty) return const SizedBox();

    // Data range is the union of both datasets.
    final dataMinX = spotsB.isEmpty
        ? spotsA.first.x
        : math.min(spotsA.first.x, spotsB.first.x);
    final dataMaxX = spotsB.isEmpty
        ? spotsA.last.x
        : math.max(spotsA.last.x, spotsB.last.x);
    final allY = [...spotsA.map((s) => s.y), ...spotsB.map((s) => s.y)];
    final dataMinY = allY.reduce(math.min);
    final dataMaxY = allY.reduce(math.max);
    final yPad = (dataMaxY - dataMinY) * 0.05;

    final viewMinX = _zoomMinX ?? dataMinX;
    final viewMaxX = _zoomMaxX ?? dataMaxX;
    final viewMinY = (_zoomMinY ?? dataMinY) - yPad;
    final viewMaxY = (_zoomMaxY ?? dataMaxY) + yPad;

    // Approximate chart area margins within the widget.
    // Left = y-axis reserved size; bottom = x-axis reserved + axis name label.
    const leftMargin   = 56.0;
    const rightMargin  = 8.0;
    const topMargin    = 8.0;
    const bottomMargin = 52.0;

    return LayoutBuilder(builder: (context, constraints) {
      final chartW = constraints.maxWidth  - leftMargin - rightMargin;
      final chartH = constraints.maxHeight - topMargin  - bottomMargin;

      double toDataX(double px) {
        if (chartW <= 0) return viewMinX;
        final frac = ((px - leftMargin) / chartW).clamp(0.0, 1.0);
        return viewMinX + frac * (viewMaxX - viewMinX);
      }

      double toDataY(double py) {
        if (chartH <= 0) return viewMinY;
        final frac = ((py - topMargin) / chartH).clamp(0.0, 1.0);
        // Y axis: top = max, bottom = min
        return viewMaxY - frac * (viewMaxY - viewMinY);
      }

      return Stack(
        children: [
          // Listener captures raw pointer events before the gesture arena,
          // so it works even though fl_chart claims the pan gesture internally.
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) {
              if (e.kind == PointerDeviceKind.mouse &&
                  e.buttons == kPrimaryMouseButton) {
                setState(() {
                  _selStart   = e.localPosition;
                  _selCurrent = e.localPosition;
                });
              }
            },
            onPointerMove: (e) {
              if (_selStart != null) {
                setState(() => _selCurrent = e.localPosition);
              }
            },
            onPointerUp: (e) {
              final s = _selStart;
              final c = _selCurrent;
              if (s != null && c != null) {
                final x1 = toDataX(s.dx); final x2 = toDataX(c.dx);
                final y1 = toDataY(s.dy); final y2 = toDataY(c.dy);
                final newMinX = math.min(x1, x2);
                final newMaxX = math.max(x1, x2);
                final newMinY = math.min(y1, y2);
                final newMaxY = math.max(y1, y2);
                if ((newMaxX - newMinX) > 0.01 && (newMaxY - newMinY) > 0.001) {
                  setState(() {
                    _zoomMinX = newMinX.clamp(dataMinX, dataMaxX);
                    _zoomMaxX = newMaxX.clamp(dataMinX, dataMaxX);
                    _zoomMinY = newMinY;
                    _zoomMaxY = newMaxY;
                  });
                }
              }
              setState(() { _selStart = null; _selCurrent = null; });
            },
            child: LineChart(
              LineChartData(
                minX: viewMinX,
                maxX: viewMaxX,
                minY: viewMinY,
                maxY: viewMaxY,
                clipData: const FlClipData.all(),
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: true),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    // Background uses fl_chart's default (Colors.blueGrey.darken(15)),
                    // always dark regardless of theme — unchanged from before.
                    getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                      final prefix = spotsB.isNotEmpty
                          ? (s.barIndex == 0 ? 'A: ' : 'B: ')
                          : '';
                      // Force white text only in light mode, where the ambient
                      // text color is dark and unreadable on the dark tooltip bg.
                      // Dark mode's ambient color already reads well unforced.
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      return LineTooltipItem(
                        '${prefix}t=${s.x.toStringAsFixed(2)}s\n'
                        '${s.y.toStringAsFixed(2)} $yUnit',
                        TextStyle(fontSize: 11, color: isDark ? null : Colors.white),
                      );
                    }).toList(),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text('Time (s)',
                        style: TextStyle(fontSize: 11)),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final label = v % 1 == 0
                            ? v.toInt().toString()
                            : v.toStringAsFixed(1);
                        return Text(label,
                            style: const TextStyle(fontSize: 10));
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      getTitlesWidget: (v, _) {
                        final label = v % 1 == 0
                            ? v.toInt().toString()
                            : v.toStringAsFixed(1);
                        return Text(label,
                            style: const TextStyle(fontSize: 10));
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spotsA,
                    isCurved: false,
                    color: colorA,
                    barWidth: 1.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                  if (spotsB.isNotEmpty)
                    LineChartBarData(
                      spots: spotsB,
                      isCurved: false,
                      color: colorB,
                      barWidth: 1.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                ],
              ),
            ),
          ),

          // Rubber-band selection box
          if (_selStart != null && _selCurrent != null)
            Positioned.fromRect(
              rect: Rect.fromPoints(_selStart!, _selCurrent!),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.15),
                  border: Border.all(color: Colors.blue.shade400, width: 1.5),
                ),
              ),
            ),

          // Reset zoom button — only shown when zoomed
          if (_isZoomed)
            Positioned(
              top: 4,
              right: 4,
              child: ElevatedButton.icon(
                onPressed: _resetZoom,
                icon: const Icon(Icons.zoom_out_map, size: 14),
                label: const Text('Reset', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _buildSummaryRow() {
    final meta = widget.data.metadata;
    final n = meta.totalCount;
    final fastSec =
        (meta.fastCount * meta.fastPeriodMs / 1000).toStringAsFixed(1);
    final totalSec = widget.data.samples.isNotEmpty
        ? widget.data.samples.last.timeSec.toStringAsFixed(1)
        : '—';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        '$n samples  •  ${meta.fastPeriodMs}ms fast / ${meta.slowPeriodMs}ms slow'
        '  •  fast: ${fastSec}s  •  total: ${totalSec}s',
        style: TextStyle(fontSize: 11, color: secondaryTextColor(context)),
      ),
    );
  }
}
