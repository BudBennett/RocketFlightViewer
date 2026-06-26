import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/flight_controller.dart';
import '../widgets/flight_chart.dart';
import '../widgets/stats_widget.dart';
import '../utils/theme_utils.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _statsVisible = true;
  Color _colorA = Colors.blue;
  Color _colorB = Colors.pinkAccent;

  @override
  Widget build(BuildContext context) {
    return Consumer<FlightController>(
      builder: (context, ctrl, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text('Import Flight'),
                      onPressed: ctrl.isBusy ? null : () => ctrl.importCsv(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.compare_arrows, size: 16),
                      label: const Text('Compare Flights'),
                      onPressed: ctrl.isBusy || ctrl.historyData == null
                          ? null
                          : () => ctrl.importCsvCompare(context),
                    ),
                  ),
                ],
              ),
            ),
            if (ctrl.historyFileName != null || ctrl.historyFileName2 != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _fileLabel(context, 'A', ctrl.historyFileName,
                          _colorA, null),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _fileLabel(context, 'B', ctrl.historyFileName2,
                          _colorB,
                          ctrl.historyFileName2 != null ? ctrl.clearHistoryCompare : null),
                    ),
                  ],
                ),
              ),
            if (ctrl.isBusy)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: LinearProgressIndicator(),
              ),
            Expanded(child: _buildContent(context, ctrl)),
          ],
        );
      },
    );
  }

  Widget _fileLabel(BuildContext context, String slot, String? name,
      Color swatchColor, VoidCallback? onClear) {
    if (name == null) return const SizedBox.shrink();
    return Row(
      children: [
        Container(
          width: 18,
          height: 3,
          decoration: BoxDecoration(
            color: swatchColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Flight $slot: $name',
            style: TextStyle(
                fontSize: 11, color: swatchColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onClear != null)
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 13,
                  color: Theme.of(context).colorScheme.outline),
            ),
          ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, FlightController ctrl) {
    final data = ctrl.historyData;
    if (data != null && !data.isEmpty) {
      if (Platform.isAndroid) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: ctrl.historyStats != null
              ? StatsWidget(
                  stats: ctrl.historyStats!,
                  stats2: ctrl.historyStats2,
                  colorA: _colorA,
                  colorB: _colorB,
                )
              : const SizedBox.shrink(),
        );
      }

      return Column(
        children: [
          Expanded(
            child: FlightChart(
              data: data,
              useImperial: ctrl.useImperial,
              data2: ctrl.historyData2,
              onColorsChanged: (a, b) => setState(() { _colorA = a; _colorB = b; }),
            ),
          ),
          if (ctrl.historyStats != null) ...[
            InkWell(
              onTap: () => setState(() => _statsVisible = !_statsVisible),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _statsVisible ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _statsVisible ? 'Hide Stats' : 'Show Stats',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_statsVisible)
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: StatsWidget(
                  stats: ctrl.historyStats!,
                  stats2: ctrl.historyStats2,
                  colorA: _colorA,
                  colorB: _colorB,
                ),
              ),
          ],
        ],
      );
    }

    return Center(
      child: Text(
        'Import a saved CSV file to view a previous flight',
        style: TextStyle(color: secondaryTextColor(context)),
      ),
    );
  }
}
