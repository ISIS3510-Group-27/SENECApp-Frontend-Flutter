import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/offline.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/location/location_service.dart';
import '../../data/models/campus_event.dart';
import 'event_directions_view_model.dart';

class EventDirectionsSheet extends StatefulWidget {
  const EventDirectionsSheet({super.key, required this.event});

  final CampusEvent event;

  static Future<void> show(BuildContext context, CampusEvent event) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppColors.background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.hero),
          ),
        ),
        builder: (_) => EventDirectionsSheet(event: event),
      );

  @override
  State<EventDirectionsSheet> createState() => _EventDirectionsSheetState();
}

class _EventDirectionsSheetState extends State<EventDirectionsSheet> {
  late final EventDirectionsViewModel _vm = EventDirectionsViewModel(
    event: widget.event,
    location: context.read<AppServices>().location,
    maps: context.read<AppServices>().maps,
  );

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  String? get _problemMessage => switch (_vm.problem) {
    null => null,
    LocationProblem.denied =>
      'Location permission was denied. You can still view the venue.',
    LocationProblem.deniedForever =>
      'Location is blocked for SENECApp. Enable it in settings, then try again.',
    LocationProblem.serviceOff =>
      'Location is off on this phone. Turn it on in settings, then try again.',
    LocationProblem.unavailable =>
      "Couldn't get your location. Try again or view the venue.",
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _vm,
    builder: (context, _) {
      final vm = _vm;
      final distance = vm.distanceMeters;
      final busy = vm.locating || vm.opening;
      final settings =
          vm.problem == LocationProblem.deniedForever ||
          vm.problem == LocationProblem.serviceOff;
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(kPageGutter),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Get directions',
                        style: AppTheme.heading(size: 20),
                      ),
                    ),
                    RoundIconButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Close directions',
                      size: 48,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(widget.event.location, style: AppTheme.heading(size: 16)),
                const SizedBox(height: 6),
                if (!vm.available)
                  Text(
                    widget.event.isCancelled
                        ? 'This event was cancelled.'
                        : 'Venue coordinates are not available yet.',
                    style: AppTheme.body(
                      size: 13,
                      color: AppColors.mutedForeground,
                    ),
                  )
                else ...[
                  if (distance != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      distance < 1000
                          ? '${distance.round()} m away'
                          : '${(distance / 1000).toStringAsFixed(1)} km away',
                      style: AppTheme.heading(size: 20),
                    ),
                    Text(
                      'Approximate straight-line distance',
                      style: AppTheme.body(
                        size: 12,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                  if (!isOnline(context)) ...[
                    const SizedBox(height: 12),
                    const OfflineNote(
                      'Distance can be checked offline. Google Maps may need a connection for directions.',
                    ),
                  ],
                  if (_problemMessage case final message?) ...[
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: AppTheme.body(
                        size: 13,
                        color: AppColors.bodyForeground,
                      ),
                    ),
                  ],
                  if (vm.error case final error?) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: AppTheme.body(size: 13, color: AppColors.primary),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (busy) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: 10),
                    Text(
                      vm.locating
                          ? 'Finding your location...'
                          : 'Opening Google Maps...',
                      style: AppTheme.body(size: 13),
                    ),
                    const SizedBox(height: 10),
                  ],
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.my_location_rounded),
                    label: Text(
                      vm.hasOrigin
                          ? 'Update my location'
                          : vm.problem == null
                          ? 'Use my location'
                          : 'Try location again',
                    ),
                    onPressed: busy ? null : vm.locate,
                  ),
                  if (settings)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Open location settings'),
                      onPressed: busy ? null : vm.openSettings,
                    ),
                  if (vm.hasOrigin) ...[
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.directions_walk_rounded),
                      label: const Text('Open walking route in Google Maps'),
                      onPressed: busy ? null : vm.openWalkingRoute,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Opening a route shares your starting point with Google Maps. SENECApp does not store it.',
                      style: AppTheme.body(
                        size: 12,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('View venue in Google Maps'),
                    onPressed: busy ? null : vm.openPlace,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
