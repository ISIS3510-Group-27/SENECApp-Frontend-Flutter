import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/selectable_chip.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/catalog.dart';
import '../../data/models/group_filters.dart';
import '../../data/repositories/catalog_repository.dart';

/// Everything Explore can filter by beyond the text and the category chip.
///
/// Changes are a draft until "Show results", so trying combinations doesn't
/// send (and log) a search for each tap.
class FiltersSheet extends StatefulWidget {
  const FiltersSheet({super.key, required this.initial, required this.catalog});

  final GroupFilters initial;
  final CatalogRepository catalog;

  /// The chosen filters, or `null` if the sheet was dismissed.
  static Future<GroupFilters?> show(
    BuildContext context, {
    required GroupFilters current,
    required CatalogRepository catalog,
  }) => showModalBottomSheet<GroupFilters>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.hero)),
    ),
    builder: (_) => FiltersSheet(initial: current, catalog: catalog),
  );

  @override
  State<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<FiltersSheet> {
  late GroupFilters _draft = widget.initial;
  late Future<(List<Interest>, List<Building>)> _catalog = _loadCatalog();

  Future<(List<Interest>, List<Building>)> _loadCatalog() async =>
      (await widget.catalog.interests(), await widget.catalog.buildings());

  Set<T> _toggled<T>(Set<T> set, T value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(kPageGutter, 20, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Filters', style: AppTheme.heading(size: 20)),
                ),
                TextButton(
                  onPressed: () => setState(() => _draft = _draft.clearSheet()),
                  child: Text(
                    'Clear',
                    style: AppTheme.body(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
              children: [
                const SectionLabel(text: 'Sort by'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final sort in GroupSort.values)
                      SelectableChip.filter(
                        label: sort.label,
                        selected: _draft.sort == sort,
                        onSelected: (_) => setState(
                          () => _draft = _draft.copyWith(sort: sort),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const SectionLabel(text: 'Show only'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SelectableChip.filter(
                      label: 'Official RSOs',
                      selected: _draft.verifiedOnly,
                      onSelected: (on) => setState(
                        () => _draft = _draft.copyWith(verifiedOnly: on),
                      ),
                    ),
                    SelectableChip.filter(
                      label: 'With upcoming events',
                      selected: _draft.withUpcomingEvents,
                      onSelected: (on) => setState(
                        () => _draft = _draft.copyWith(withUpcomingEvents: on),
                      ),
                    ),
                  ],
                ),
                FutureBuilder(
                  future: _catalog,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ErrorBlock(
                        message: 'Interests and buildings are unavailable.',
                        onRetry: () =>
                            setState(() => _catalog = _loadCatalog()),
                      );
                    }
                    final (interests, buildings) =
                        snapshot.data ??
                        (const <Interest>[], const <Building>[]);
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const LoadingBlock();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        const SectionLabel(text: 'Interests'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final interest in interests)
                              SelectableChip.filter(
                                label: interest.name,
                                selected: _draft.interestIds.contains(
                                  interest.id,
                                ),
                                onSelected: (_) => setState(
                                  () => _draft = _draft.copyWith(
                                    interestIds: _toggled(
                                      _draft.interestIds,
                                      interest.id,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const SectionLabel(text: 'Meets in'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final building in buildings)
                              SelectableChip.filter(
                                label: building.name,
                                selected: _draft.buildingCodes.contains(
                                  building.code,
                                ),
                                onSelected: (_) => setState(
                                  () => _draft = _draft.copyWith(
                                    buildingCodes: _toggled(
                                      _draft.buildingCodes,
                                      building.code,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 16),
            child: PrimaryButton(
              label: 'Show results',
              onPressed: () => Navigator.of(context).pop(_draft),
            ),
          ),
        ],
      ),
    );
  }
}
