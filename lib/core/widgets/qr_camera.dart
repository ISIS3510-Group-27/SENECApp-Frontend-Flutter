import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Builds a live camera view that calls `onCode` with the text of each QR
/// code it sees. Part of `AppServices`, so tests can swap the camera for a
/// fake.
typedef QrCameraBuilder =
    Widget Function(BuildContext context, ValueChanged<String> onCode);

/// The phone's camera, reading QR codes with `mobile_scanner`.
Widget mobileScannerCamera(BuildContext context, ValueChanged<String> onCode) =>
    _MobileScannerCamera(onCode: onCode);

class _MobileScannerCamera extends StatefulWidget {
  const _MobileScannerCamera({required this.onCode});

  final ValueChanged<String> onCode;

  @override
  State<_MobileScannerCamera> createState() => _MobileScannerCameraState();
}

class _MobileScannerCameraState extends State<_MobileScannerCamera> {
  // QR only, and each code once: holding the phone still shouldn't send the
  // same check-in over and over.
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          if (barcode.rawValue case final raw?) widget.onCode(raw);
        }
      },
      errorBuilder: (context, error) => _CameraProblem(error: error),
    );
  }
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Camera access is off for SENECApp. Allow it in Settings, or type '
            'the code instead.',
      MobileScannerErrorCode.unsupported =>
        "This device can't scan codes. Type the code instead.",
      _ => "The camera didn't start. Try again, or type the code instead.",
    };

    return ColoredBox(
      color: AppColors.card,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                size: 36,
                color: AppColors.mutedForeground,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTheme.body(
                  size: 13,
                  height: 1.4,
                  color: AppColors.bodyForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
