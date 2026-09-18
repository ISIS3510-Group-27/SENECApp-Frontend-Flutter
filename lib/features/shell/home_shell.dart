import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../create_rso/create_rso_screen.dart';
import '../discover/discover_screen.dart';
import '../events/events_screen.dart';
import '../my_rsos/my_rsos_screen.dart';
import '../profile/profile_screen.dart';

/// The four top-level destinations.
///
/// Flat navigation: four peers, each one tap away and in thumb reach. A drawer
/// was rejected because it would bury Discover behind a hamburger, and four
/// destinations are well under the five that justify one.
enum AppTab {
  discover('Discover', Icons.home_outlined, Icons.home_rounded),
  events('Events', Icons.calendar_today_outlined, Icons.calendar_month_rounded),
  myRsos('My RSOs', Icons.groups_outlined, Icons.groups_rounded),
  profile('Profile', Icons.person_outline_rounded, Icons.person_rounded);

  const AppTab(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;

  /// The filled variant. Weight is the second of the three redundant signals
  /// that mark the active tab, alongside colour and the dot indicator.
  final IconData activeIcon;
}

/// Hosts the bottom navigation bar and one [Navigator] per tab.
///
/// The per-tab navigator is what makes reverse navigation *contextual*: opening
/// an organization from Events pushes onto the Events stack, so backing out
/// returns to Events rather than to Discover. It also keeps each tab's scroll
/// position and filters alive while the student moves between them.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppTab _current = AppTab.discover;

  final _navigatorKeys = {
    for (final tab in AppTab.values) tab: GlobalKey<NavigatorState>(),
  };

  NavigatorState? get _currentNavigator =>
      _navigatorKeys[_current]!.currentState;

  void _onTabSelected(AppTab tab) {
    if (tab == _current) {
      // Tapping the active tab returns to its root, the standard Android
      // shortcut out of a detail screen.
      _currentNavigator?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _current = tab);
  }

  /// Android's system back gesture, in priority order: unwind the current tab's
  /// stack, then fall back to Discover, then leave the app.
  Future<void> _handleBack(bool didPop, Object? result) async {
    if (didPop) return;

    if (await _currentNavigator?.maybePop() ?? false) return;

    if (_current != AppTab.discover) {
      setState(() => _current = AppTab.discover);
      return;
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _current.index,
            children: [
              for (final tab in AppTab.values)
                _TabNavigator(navigatorKey: _navigatorKeys[tab]!, tab: tab),
            ],
          ),
        ),
        bottomNavigationBar: _BottomNav(
          current: _current,
          onSelected: _onTabSelected,
        ),
      ),
    );
  }
}

/// A tab's own navigation stack. Its root is the tab's screen; details and
/// forms push on top of it.
class _TabNavigator extends StatelessWidget {
  const _TabNavigator({required this.navigatorKey, required this.tab});

  final GlobalKey<NavigatorState> navigatorKey;
  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => switch (tab) {
          AppTab.discover => DiscoverScreen(
            onCreateRso: () => navigatorKey.currentState!.push(
              MaterialPageRoute<void>(builder: (_) => const CreateRsoScreen()),
            ),
          ),
          AppTab.events => const EventsScreen(),
          AppTab.myRsos => const MyRsosScreen(),
          AppTab.profile => const ProfileScreen(),
        },
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.current, required this.onSelected});

  final AppTab current;
  final ValueChanged<AppTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 10),
          child: Row(
            children: [
              // Equal quarters rather than intrinsic widths: "Discover" is
              // wider than "Events", and at 390px the natural sizes overflow.
              for (final tab in AppTab.values)
                Expanded(
                  child: _NavItem(
                    tab: tab,
                    active: tab == current,
                    onTap: () => onSelected(tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final AppTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.mutedForeground;

    return Semantics(
      selected: active,
      button: true,
      label: tab.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 26,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Icon(
                      active ? tab.activeIcon : tab.icon,
                      size: 22,
                      color: color,
                    ),
                    if (active)
                      Positioned(
                        bottom: 0,
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 10,
                  weight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
