import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'app_services.dart';
import 'core/assets/asset_catalog.dart';
import 'core/theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read the asset manifest before the first frame so organization art that is
  // present is used immediately
  await AssetCatalog.load();

  // The canvas runs behind the system bars, so their icons need to be light.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final services = await AppServices.create();

  // Errors nobody caught go to the analytics queue, which is saved on the
  // phone right away: if the app dies, they are sent on the next launch
  // (BQ1, BQ14). Framework errors (a layout overflow...) don't stop the app;
  // uncaught exceptions count as crashes.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    services.analytics.error(details.exception);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    services.analytics.error(error, fatal: true);
    return false; // Still reported the usual way.
  };

  runApp(SenecApp(services: services));
}
