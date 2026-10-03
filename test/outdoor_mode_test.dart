import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/data/sensors/ambient_light.dart';
import 'package:senecapp/state/outdoor_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLightSensor implements AmbientLightSensor {
  final controller = StreamController<double>.broadcast();

  @override
  Stream<double> get lux => controller.stream;
}

void main() {
  late FakeLightSensor sensor;
  late OutdoorMode mode;

  Future<OutdoorMode> start({Map<String, Object> saved = const {}}) async {
    SharedPreferences.setMockInitialValues(saved);
    sensor = FakeLightSensor();
    mode = OutdoorMode(
      sensor: sensor,
      preferences: await SharedPreferences.getInstance(),
    )..start();
    addTearDown(mode.dispose);
    return mode;
  }

  Future<void> light(WidgetTester tester, double lux, Duration wait) async {
    sensor.controller.add(lux);
    await tester.pump();
    await tester.pump(wait);
  }

  testWidgets('turns on after bright light holds, and off after it fades', (
    tester,
  ) async {
    await start();

    await light(tester, 25000, const Duration(seconds: 1));
    expect(mode.active, isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(mode.active, isTrue);
    expect(mode.sensorAvailable, isTrue);

    await light(tester, 5000, const Duration(seconds: 5));
    expect(mode.active, isTrue);

    await light(tester, 800, const Duration(seconds: 4));
    expect(mode.active, isFalse);
  });

  testWidgets('a short flash of light changes nothing', (tester) async {
    await start();

    await light(tester, 25000, const Duration(seconds: 1));
    await light(tester, 400, const Duration(seconds: 5));

    expect(mode.active, isFalse);
  });

  testWidgets('the setting overrides the sensor and is remembered', (
    tester,
  ) async {
    await start();

    await mode.setSetting(OutdoorSetting.on);
    expect(mode.active, isTrue);
    await mode.setSetting(OutdoorSetting.off);
    await light(tester, 25000, const Duration(seconds: 5));
    expect(mode.active, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('outdoor_mode.setting'), 'off');
  });

  testWidgets('a phone without the sensor reports it', (tester) async {
    await start();

    sensor.controller.addError(Exception('NO_SENSOR'));
    await tester.pump();

    expect(mode.sensorAvailable, isFalse);
    expect(mode.active, isFalse);
  });
}
