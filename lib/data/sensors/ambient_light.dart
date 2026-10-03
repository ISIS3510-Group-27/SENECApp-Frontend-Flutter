import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class AmbientLightSensor {
  Stream<double> get lux;
}

class PlatformAmbientLightSensor implements AmbientLightSensor {
  const PlatformAmbientLightSensor();

  static const _channel = EventChannel('senecapp/ambient_light');

  @override
  Stream<double> get lux {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const Stream.empty();
    }
    return _channel.receiveBroadcastStream().map((v) => (v as num).toDouble());
  }
}

class NoAmbientLightSensor implements AmbientLightSensor {
  const NoAmbientLightSensor();

  @override
  Stream<double> get lux => const Stream.empty();
}
