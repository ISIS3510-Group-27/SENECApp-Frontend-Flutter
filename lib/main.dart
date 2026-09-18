import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/assets/asset_catalog.dart';
import 'core/theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read the asset manifest before the first frame so organization art that is
  // present is used immediately, and art that is missing falls back cleanly
  // instead of flashing.
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

  runApp(const SenecApp());
}
