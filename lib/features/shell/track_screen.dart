import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../data/analytics/analytics.dart';
import 'home_shell.dart';

/// Records a `screen_view` when the student sees this screen with its
/// content (BQ1, BQ11, BQ14).
///
/// [ready] says the content is there: data loaded, or an error shown in its
/// place. The load time runs from when the screen was shown until then. For
/// a tab's root screen, pass [tab]: tabs are all built at launch, and only
/// count once the student switches to them. Coming back to a tab that already
/// loaded counts as a view, without a load time.
class TrackScreen extends StatefulWidget {
  const TrackScreen({
    super.key,
    required this.name,
    required this.child,
    this.ready = true,
    this.tab,
  });

  /// One of [Screens].
  final String name;

  final bool ready;
  final AppTab? tab;
  final Widget child;

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  late final Analytics _analytics = context.read<AppServices>().analytics;
  TabSelection? _tabs;

  final _sinceShown = Stopwatch();
  bool _wasVisible = false;
  bool _loadTimeSent = false;

  bool get _visible => widget.tab == null || _tabs?.value == widget.tab;

  @override
  void initState() {
    super.initState();
    if (widget.tab != null) {
      _tabs = context.read<TabSelection>()..addListener(_onTabChanged);
    }
    _wasVisible = _visible;
    if (_visible) {
      _sinceShown.start();
      if (widget.ready) _reportAfterFrame();
    }
  }

  @override
  void didUpdateWidget(TrackScreen old) {
    super.didUpdateWidget(old);
    if (!old.ready && widget.ready && _visible) _reportAfterFrame();
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    final visible = _visible;
    if (visible && !_wasVisible) {
      if (!_loadTimeSent) {
        _sinceShown
          ..reset()
          ..start();
      }
      // A detail screen pushed on this tab is what's showing, not this one.
      final onTop = ModalRoute.of(context)?.isCurrent ?? true;
      if (widget.ready && onTop) _report();
    }
    _wasVisible = visible;
  }

  /// Counts the view once the content has actually been drawn.
  void _reportAfterFrame() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _report());

  void _report() {
    if (!mounted) return;
    _analytics.screenView(
      widget.name,
      loadTime: _loadTimeSent ? null : _sinceShown.elapsed,
    );
    _loadTimeSent = true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Records an error the student was shown on [screen] (BQ1, BQ14).
void reportError(
  BuildContext context,
  Object error, {
  required String screen,
}) => context.read<AppServices>().analytics.error(error, screen: screen);
