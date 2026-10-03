import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/sensors/ambient_light.dart';

enum OutdoorSetting { auto, on, off }

class OutdoorMode extends ChangeNotifier with WidgetsBindingObserver {
  OutdoorMode({
    required AmbientLightSensor sensor,
    SharedPreferences? preferences,
    this.hold = const Duration(seconds: 3),
  }) : _sensor = sensor,
       _preferences = preferences;

  static const enterLux = 10000.0;
  static const exitLux = 3000.0;
  static const _settingKey = 'outdoor_mode.setting';

  final AmbientLightSensor _sensor;
  final SharedPreferences? _preferences;
  final Duration hold;

  OutdoorSetting _setting = OutdoorSetting.auto;
  bool _bright = false;
  bool? _sensorAvailable;
  double? _lastLux;
  StreamSubscription<double>? _subscription;
  Timer? _pending;
  bool _started = false;

  OutdoorSetting get setting => _setting;

  bool? get sensorAvailable => _sensorAvailable;

  double? get lastLux => _lastLux;

  bool get active => switch (_setting) {
    OutdoorSetting.on => true,
    OutdoorSetting.off => false,
    OutdoorSetting.auto => _bright,
  };

  void start() {
    if (_started) return;
    _started = true;
    final saved = _preferences?.getString(_settingKey);
    _setting = OutdoorSetting.values.asNameMap()[saved] ?? OutdoorSetting.auto;
    WidgetsBinding.instance.addObserver(this);
    _listen();
  }

  Future<void> setSetting(OutdoorSetting setting) async {
    if (setting == _setting) return;
    _setting = setting;
    _pending?.cancel();
    if (setting == OutdoorSetting.auto) {
      _listen();
    } else {
      _stopListening();
    }
    notifyListeners();
    await _preferences?.setString(_settingKey, setting.name);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _listen();
    } else if (state == AppLifecycleState.paused) {
      _stopListening();
    }
  }

  void _listen() {
    if (_setting != OutdoorSetting.auto || _subscription != null) return;
    if (_sensorAvailable == false) return;
    _subscription = _sensor.lux.listen(
      onLux,
      onError: (Object _) {
        _sensorAvailable = false;
        _stopListening();
        notifyListeners();
      },
      cancelOnError: true,
    );
  }

  void _stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _pending?.cancel();
    _pending = null;
  }

  @visibleForTesting
  void onLux(double lux) {
    _lastLux = lux;
    if (_sensorAvailable != true) {
      _sensorAvailable = true;
      notifyListeners();
    }
    final wantsBright = _bright ? lux > exitLux : lux >= enterLux;
    if (wantsBright == _bright) {
      _pending?.cancel();
      _pending = null;
      return;
    }
    _pending ??= Timer(hold, () {
      _pending = null;
      _bright = wantsBright;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _stopListening();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class OutdoorView extends StatefulWidget {
  const OutdoorView({super.key, required this.mode, required this.child});

  final OutdoorMode mode;
  final Widget child;

  static const _contrast = 1.3;
  static const _lift = 128 * (1 - _contrast) + 18;
  static const matrix = <double>[
    _contrast, 0, 0, 0, _lift,
    0, _contrast, 0, 0, _lift,
    0, 0, _contrast, 0, _lift,
    0, 0, 0, 1, 0,
  ];

  @override
  State<OutdoorView> createState() => _OutdoorViewState();
}

class _OutdoorViewState extends State<OutdoorView> {
  final _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.mode,
      builder: (context, _) {
        final child = KeyedSubtree(key: _childKey, child: widget.child);
        if (!widget.mode.active) return child;
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            boldText: true,
            textScaler: TextScaler.linear(
              media.textScaler.scale(14) / 14 * 1.1,
            ),
          ),
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix(OutdoorView.matrix),
            child: child,
          ),
        );
      },
    );
  }
}
