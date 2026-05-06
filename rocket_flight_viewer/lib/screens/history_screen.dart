import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/flight_controller.dart';
import '../widgets/flight_chart.dart';
import '../widgets/stats_widget.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _statsVisible = true;

  @override
  Widget build(BuildContext context) {
    return Consumer<FlightController>(
      builder: (context, ctrl, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Upload CSV'),
                onPressed: ctrl.isBusy ? null : () => ctrl.importCsv(),
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

  Widget _buildContent(BuildContext context, FlightController ctrl) {
    final data = ctrl.historyData;
    if (data != null && !data.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: FlightChart(
              data: data,
              calib: ctrl.historyCalib,
              useImperial: ctrl.useImperial,
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
                  calib: ctrl.historyCalib,
                ),
              ),
          ],
        ],
      );
    }

    return const Center(
      child: Text(
        'Upload a saved CSV file to view a previous flight',
        style: TextStyle(color: Colors.grey),
      ),
    );
  }
}
