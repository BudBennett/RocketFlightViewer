import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/flight_controller.dart';
import '../widgets/flight_chart.dart';
import '../widgets/live_widget.dart';
import '../widgets/stats_widget.dart';
import '../widgets/monitor_widget.dart';
import 'settings_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showMonitor = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<FlightController>(
      builder: (context, ctrl, _) {
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Rocket Flight Viewer'),
              actions: [
                IconButton(
                  icon: Icon(
                    Icons.terminal,
                    color: _showMonitor ? Theme.of(context).colorScheme.primary : null,
                  ),
                  tooltip: 'Toggle monitor',
                  onPressed: () => setState(() => _showMonitor = !_showMonitor),
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.rocket_launch), text: 'Flight Data'),
                  Tab(icon: Icon(Icons.settings), text: 'Settings'),
                  Tab(icon: Icon(Icons.history), text: 'History'),
                ],
              ),
            ),
            body: Column(
              children: [
                _ConnectionBar(ctrl: ctrl),
                _StatusBar(ctrl: ctrl),
                Expanded(
                  child: TabBarView(
                    children: [
                      _FlightDataTab(ctrl: ctrl),
                      const SettingsScreen(),
                      const HistoryScreen(),
                    ],
                  ),
                ),
                if (_showMonitor)
                  SizedBox(
                    height: 200,
                    child: MonitorWidget(
                      entries: ctrl.commLog,
                      onClear: ctrl.clearLog,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Flight Data tab
// ---------------------------------------------------------------------------

class _FlightDataTab extends StatefulWidget {
  final FlightController ctrl;

  const _FlightDataTab({required this.ctrl});

  @override
  State<_FlightDataTab> createState() => _FlightDataTabState();
}

class _FlightDataTabState extends State<_FlightDataTab> {
  bool _statsVisible = true;

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return Column(
      children: [
        if (ctrl.isConnected) _FlightDataActionRow(ctrl: ctrl),
        Expanded(child: _buildContent(context, ctrl)),
      ],
    );
  }

  Widget _buildContent(BuildContext context, FlightController ctrl) {
    if (ctrl.liveActive) {
      return LiveWidget(
        sample: ctrl.liveSample,
        history: ctrl.liveHistory,
        calib: ctrl.calib,
        useImperial: ctrl.useImperial,
      );
    }

    if (ctrl.isBusy) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(ctrl.statusMessage, style: const TextStyle(fontSize: 13)),
          if (ctrl.downloadProgress > 0) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: LinearProgressIndicator(value: ctrl.downloadProgress),
            ),
          ],
        ],
      );
    }

    if (ctrl.flightData != null && !ctrl.flightData!.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.save_alt, size: 16),
                label: const Text('Save CSV'),
                onPressed: () => ctrl.exportCsv(),
              ),
            ),
          ),
          Expanded(
            child: FlightChart(
              data: ctrl.flightData!,
              calib: ctrl.calib,
              useImperial: ctrl.useImperial,
            ),
          ),
          if (ctrl.flightStats != null) ...[
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
                  stats: ctrl.flightStats!,
                  calib: ctrl.calib,
                ),
              ),
          ],
        ],
      );
    }

    return Center(
      child: Text(
        ctrl.isConnected
            ? 'Press Download Data to retrieve flight data'
            : 'Select a serial port and connect',
      ),
    );
  }
}

class _FlightDataActionRow extends StatelessWidget {
  final FlightController ctrl;

  const _FlightDataActionRow({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final disableNonLive = ctrl.isBusy || ctrl.liveActive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (ctrl.hasStorage)
            _ActionButton(
              label: 'Download Data',
              icon: Icons.download,
              busy: disableNonLive,
              onPressed: () => ctrl.downloadFlight(),
            ),
          if (ctrl.hasStorage)
            _ActionButton(
              label: 'Erase',
              icon: Icons.delete_outline,
              busy: disableNonLive,
              danger: true,
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Erase storage?'),
                    content: const Text(
                      'This will permanently delete all recorded flight data. '
                      'Download first if you need the data.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Erase'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await ctrl.eraseStorage();
              },
            ),
          _ActionButton(
            label: ctrl.liveActive ? 'Stop Live' : 'Live',
            icon: ctrl.liveActive ? Icons.stop_circle_outlined : Icons.sensors,
            busy: ctrl.isBusy,
            onPressed: () {
              if (ctrl.liveActive) {
                ctrl.stopLive();
              } else {
                ctrl.startLive();
              }
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connection bar
// ---------------------------------------------------------------------------

class _ConnectionBar extends StatefulWidget {
  final FlightController ctrl;
  const _ConnectionBar({required this.ctrl});

  @override
  State<_ConnectionBar> createState() => _ConnectionBarState();
}

class _ConnectionBarState extends State<_ConnectionBar> {
  List<String> _ports = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() => _ports = widget.ctrl.availablePorts);
    if (!_ports.contains(widget.ctrl.selectedPort)) {
      widget.ctrl.selectPort(_ports.isNotEmpty ? _ports.first : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh port list',
            onPressed: ctrl.isBusy ? null : _refresh,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _ports.contains(ctrl.selectedPort) ? ctrl.selectedPort : null,
              hint: const Text('Select port'),
              items: _ports
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: ctrl.isConnected || ctrl.isBusy
                  ? null
                  : (p) => ctrl.selectPort(p),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: ctrl.isBusy
                ? null
                : ctrl.isConnected
                    ? ctrl.disconnect
                    : ctrl.connect,
            style: ElevatedButton.styleFrom(
              backgroundColor: ctrl.isBusy
                  ? null
                  : ctrl.isConnected
                      ? Colors.red[700]
                      : Colors.green[700],
              foregroundColor: ctrl.isBusy ? null : Colors.white,
            ),
            child: Text(ctrl.isConnected ? 'Disconnect' : 'Connect'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status bar
// ---------------------------------------------------------------------------

class _StatusBar extends StatelessWidget {
  final FlightController ctrl;
  const _StatusBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: ctrl.isError
          ? Colors.orange.withOpacity(0.35)
          : ctrl.isBusy
              ? cs.secondaryContainer.withOpacity(0.4)
              : ctrl.isConnected
                  ? cs.primaryContainer.withOpacity(0.4)
                  : cs.surfaceContainerHighest.withOpacity(0.4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(
            ctrl.isError
                ? Icons.cancel
                : ctrl.isBusy
                    ? Icons.hourglass_top
                    : ctrl.isConnected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
            size: 14,
            color: ctrl.isError
                ? Colors.red[400]
                : ctrl.isBusy
                    ? cs.secondary
                    : ctrl.isConnected
                        ? Colors.green[400]
                        : cs.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ctrl.statusMessage,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared action button
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final bool danger;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      onPressed: busy ? null : onPressed,
      style: danger
          ? OutlinedButton.styleFrom(foregroundColor: Colors.red)
          : null,
    );
  }
}
