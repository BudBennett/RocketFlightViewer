import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/flight_controller.dart';
import '../utils/theme_utils.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

const _lpfLabels = [
  'ODR/4  — 26 Hz',
  'ODR/10 — 10 Hz',
  'ODR/20 — 5 Hz',
  'ODR/45 — 2.3 Hz',
  'ODR/100 — 1 Hz',
  'ODR/200 — 0.5 Hz',
  'ODR/400 — 0.26 Hz',
  'ODR/800 — 0.13 Hz',
];

const _odrLabels = {
  0x02: '50 Hz',
  0x03: '25 Hz',
  0x04: '10 Hz',
};

const _odrHz = {
  0x02: 50.0,
  0x03: 25.0,
  0x04: 10.0,
};

/// Maximum allowed fast-phase duration in seconds: lesser of 255 (uint8 max)
/// and the number of seconds that fills storage at the configured sample rate.
int _maxFastMaxS(int? productType, int odrSel) {
  if (productType == null) return 255;
  final storageBytes = productType == 3 ? 131072 : 65536;
  const sampleBytes = 15;
  final fastHz = _odrHz[odrSel] ?? 50.0;
  final limit = (storageBytes / (fastHz * sampleBytes)).floor();
  return limit < 255 ? limit : 255;
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _thrController = TextEditingController();
  bool _thrChanged = false;
  int? _lastSyncedThrMg;
  int _lpfSetting = 1; // default ODR/10
  int? _lastSyncedLpf;
  final _fastMaxController = TextEditingController();
  bool _fastMaxChanged = false;
  int? _lastSyncedFastMax;
  int _odrSel = 0x02; // default 50 Hz
  int? _lastSyncedOdrSel;
  int _launchConfirm = 3; // default 3 samples
  int? _lastSyncedLaunchConfirm;

  @override
  void dispose() {
    _thrController.dispose();
    _fastMaxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FlightController>(
      builder: (context, ctrl, _) {
        // Sync local state from controller, but only on actual changes to avoid
        // overwriting the field on every live-poll rebuild.
        if (ctrl.configThrMg == null && _lastSyncedThrMg != null) {
          _lastSyncedThrMg = null;
          _thrController.clear();
          _thrChanged = false;
        } else if (ctrl.configThrMg != null && ctrl.configThrMg != _lastSyncedThrMg) {
          _lastSyncedThrMg = ctrl.configThrMg;
          if (!_thrChanged) _thrController.text = ctrl.configThrMg.toString();
        }
        if (ctrl.configLpfSetting == null && _lastSyncedLpf != null) {
          _lastSyncedLpf = null;
          _lpfSetting = 1;
        } else if (ctrl.configLpfSetting != null && ctrl.configLpfSetting != _lastSyncedLpf) {
          _lastSyncedLpf = ctrl.configLpfSetting;
          _lpfSetting = ctrl.configLpfSetting!.clamp(0, 7);
        }
        if (ctrl.configFastMaxS == null && _lastSyncedFastMax != null) {
          _lastSyncedFastMax = null;
          _fastMaxController.clear();
          _fastMaxChanged = false;
        } else if (ctrl.configFastMaxS != null && ctrl.configFastMaxS != _lastSyncedFastMax) {
          _lastSyncedFastMax = ctrl.configFastMaxS;
          if (!_fastMaxChanged) _fastMaxController.text = ctrl.configFastMaxS.toString();
        }
        if (ctrl.configOdrSel == null && _lastSyncedOdrSel != null) {
          _lastSyncedOdrSel = null;
          _odrSel = 0x02;
        } else if (ctrl.configOdrSel != null && ctrl.configOdrSel != _lastSyncedOdrSel) {
          _lastSyncedOdrSel = ctrl.configOdrSel;
          _odrSel = ctrl.configOdrSel!.clamp(0x02, 0x04);
        }
        if (ctrl.configLaunchConfirmSamples == null && _lastSyncedLaunchConfirm != null) {
          _lastSyncedLaunchConfirm = null;
          _launchConfirm = 3;
        } else if (ctrl.configLaunchConfirmSamples != null && ctrl.configLaunchConfirmSamples != _lastSyncedLaunchConfirm) {
          _lastSyncedLaunchConfirm = ctrl.configLaunchConfirmSamples;
          _launchConfirm = ctrl.configLaunchConfirmSamples!.clamp(1, 5);
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ----------------------------------------------------------------
            // Payload settings
            // ----------------------------------------------------------------
            Text(
              'Payload Settings',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Launch Threshold',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Net acceleration above resting gravity to detect launch. Valid range: 500–10000 mg.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: secondaryTextColor(context)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _thrController,
                            enabled: ctrl.isConnected,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: ctrl.isConnected ? 'e.g. 2000' : 'Not connected',
                              suffixText: 'mg',
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() => _thrChanged = true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: (_thrChanged &&
                                  ctrl.isConnected &&
                                  !ctrl.isBusy &&
                                  !ctrl.liveActive)
                              ? () async {
                                  final val =
                                      int.tryParse(_thrController.text);
                                  if (val != null &&
                                      val >= 500 &&
                                      val <= 10000) {
                                    await ctrl.setConfig(
                                      val,
                                      ctrl.configLpfSetting ?? 1,
                                      int.tryParse(_fastMaxController.text) ?? ctrl.configFastMaxS ?? 30,
                                      _odrSel,
                                      _launchConfirm,
                                    );
                                    setState(() => _thrChanged = false);
                                  }
                                }
                              : null,
                          child: const Text('Update'),
                        ),
                      ],
                    ),
                    if (!ctrl.isConnected)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Connect to payload to read or update',
                          style: TextStyle(color: secondaryTextColor(context), fontSize: 12),
                        ),
                      )
                    else if (ctrl.liveActive)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Stop Live mode (Payload tab) before updating',
                          style: TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text('Accel LPF2 Bandwidth',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Lower frequency = more filtering. Use lower BW for larger rockets.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: secondaryTextColor(context)),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      value: _lpfSetting,
                      isExpanded: true,
                      items: List.generate(8, (i) => DropdownMenuItem(
                        value: i,
                        child: Text(_lpfLabels[i]),
                      )),
                      onChanged: (ctrl.isConnected && !ctrl.isBusy && !ctrl.liveActive)
                          ? (v) {
                              if (v != null) {
                                setState(() => _lpfSetting = v);
                                ctrl.setConfig(
                                  int.tryParse(_thrController.text) ?? ctrl.configThrMg ?? 2000,
                                  v,
                                  int.tryParse(_fastMaxController.text) ?? ctrl.configFastMaxS ?? 30,
                                  _odrSel,
                                  _launchConfirm,
                                );
                              }
                            }
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text('Fast Sample Rate',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Lower rates extend fast-phase capacity at the cost of time resolution.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: secondaryTextColor(context)),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      value: _odrSel,
                      isExpanded: true,
                      items: _odrLabels.entries.map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      )).toList(),
                      onChanged: (ctrl.isConnected && !ctrl.isBusy && !ctrl.liveActive)
                          ? (v) {
                              if (v != null) {
                                setState(() => _odrSel = v);
                                ctrl.setConfig(
                                  int.tryParse(_thrController.text) ?? ctrl.configThrMg ?? 2000,
                                  _lpfSetting,
                                  int.tryParse(_fastMaxController.text) ?? ctrl.configFastMaxS ?? 30,
                                  v,
                                  _launchConfirm,
                                );
                              }
                            }
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text('Fast Phase Duration',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Builder(builder: (context) {
                      final hz = _odrLabels[_odrSel] ?? '50 Hz';
                      return Text(
                        'Maximum duration of $hz recording (launch through apogee). '
                        'Apogee detection ends the fast phase earlier when detected.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: secondaryTextColor(context)),
                      );
                    }),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _fastMaxController,
                            enabled: ctrl.isConnected,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: ctrl.isConnected ? 'e.g. 30' : 'Not connected',
                              suffixText: 's',
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() => _fastMaxChanged = true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: (_fastMaxChanged &&
                                  ctrl.isConnected &&
                                  !ctrl.isBusy &&
                                  !ctrl.liveActive)
                              ? () async {
                                  final val = int.tryParse(_fastMaxController.text);
                                  final maxS = _maxFastMaxS(ctrl.productType, _odrSel);
                                  if (val != null && val >= 5 && val <= maxS) {
                                    await ctrl.setConfig(
                                      int.tryParse(_thrController.text) ?? ctrl.configThrMg ?? 2000,
                                      _lpfSetting,
                                      val,
                                      _odrSel,
                                      _launchConfirm,
                                    );
                                    setState(() => _fastMaxChanged = false);
                                  }
                                }
                              : null,
                          child: const Text('Update'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Builder(builder: (context) {
                      final enteredVal = int.tryParse(_fastMaxController.text);
                      final fastMax = enteredVal ?? ctrl.configFastMaxS;
                      final pt = ctrl.productType;
                      final maxS = _maxFastMaxS(pt, _odrSel);
                      if (fastMax == null || pt == null) {
                        return Text(
                          'Range: 5–$maxS s. Connect to see capacity estimate.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: secondaryTextColor(context)),
                        );
                      }
                      final storageBytes = pt == 3 ? 131072 : 65536;
                      const sampleBytes = 15;
                      final fastHz = _odrHz[_odrSel] ?? 50.0;
                      final fastBytesMax = (fastMax * fastHz * sampleBytes).round();
                      final fastSamples = (fastMax * fastHz).round();
                      final hzLabel = _odrLabels[_odrSel] ?? '50 Hz';
                      if (fastMax > maxS) {
                        return Text(
                          'Max allowed: $maxS s at $hzLabel — enter $maxS or less.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange),
                        );
                      }
                      if (fastBytesMax >= storageBytes) {
                        return Text(
                          '$fastMax s at $hzLabel fills storage — no slow phase capacity.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange),
                        );
                      }
                      final slowSamples = (storageBytes - fastBytesMax) ~/ sampleBytes;
                      final slowMin = slowSamples ~/ 60;
                      return Text(
                        'Up to $fastSamples fast samples ($fastMax s at $hzLabel). '
                        'At least $slowMin min slow recording remaining.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: secondaryTextColor(context)),
                      );
                    }),
                    const SizedBox(height: 16),
                    Text('Launch Confirmation',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Consecutive IMU samples above threshold to confirm launch. Lower = easier to trigger.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: secondaryTextColor(context)),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      value: _launchConfirm,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1 sample  — easiest (hand toss)')),
                        DropdownMenuItem(value: 2, child: Text('2 samples')),
                        DropdownMenuItem(value: 3, child: Text('3 samples — default')),
                        DropdownMenuItem(value: 4, child: Text('4 samples')),
                        DropdownMenuItem(value: 5, child: Text('5 samples — most robust')),
                      ],
                      onChanged: (ctrl.isConnected && !ctrl.isBusy && !ctrl.liveActive)
                          ? (v) {
                              if (v != null) {
                                setState(() => _launchConfirm = v);
                                ctrl.setConfig(
                                  int.tryParse(_thrController.text) ?? ctrl.configThrMg ?? 2000,
                                  _lpfSetting,
                                  int.tryParse(_fastMaxController.text) ?? ctrl.configFastMaxS ?? 30,
                                  _odrSel,
                                  v,
                                );
                              }
                            }
                          : null,
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.restart_alt, size: 16),
                        label: const Text('Reset to Defaults'),
                        style: TextButton.styleFrom(foregroundColor: secondaryTextColor(context)),
                        onPressed: (ctrl.isConnected && !ctrl.isBusy && !ctrl.liveActive)
                            ? () async {
                                const defaultThr = 2000;
                                const defaultLpf = 1;
                                const defaultFastMax = 30;
                                const defaultOdrSel = 0x02;
                                const defaultLaunchConfirm = 3;
                                await ctrl.setConfig(defaultThr, defaultLpf, defaultFastMax, defaultOdrSel, defaultLaunchConfirm);
                                setState(() {
                                  _thrController.text = defaultThr.toString();
                                  _thrChanged = false;
                                  _lpfSetting = defaultLpf;
                                  _fastMaxController.text = defaultFastMax.toString();
                                  _fastMaxChanged = false;
                                  _odrSel = defaultOdrSel;
                                  _launchConfirm = defaultLaunchConfirm;
                                });
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ----------------------------------------------------------------
            // App settings
            // ----------------------------------------------------------------
            Text(
              'App Settings',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Theme'),
                    trailing: DropdownButton<ThemeMode>(
                      value: ctrl.themeMode,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(
                            value: ThemeMode.system, child: Text('System')),
                        DropdownMenuItem(
                            value: ThemeMode.light, child: Text('Light')),
                        DropdownMenuItem(
                            value: ThemeMode.dark, child: Text('Dark')),
                      ],
                      onChanged: (v) {
                        if (v != null) ctrl.setThemeMode(v);
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Units'),
                    subtitle: Text(
                        ctrl.useImperial ? 'Imperial (ft, lbf)' : 'Metric (m, N)'),
                    value: ctrl.useImperial,
                    onChanged: (v) => ctrl.setUnits(v),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
