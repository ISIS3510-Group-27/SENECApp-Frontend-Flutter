import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/format/dates.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/offline.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/admin_request.dart';
import '../../data/models/rso.dart';
import '../shell/track_screen.dart';

/// Members asking to become admins of [rso], for its admins to approve or
/// decline. Pops with `true` when anything was decided, so the group page
/// can refresh its count.
class AdminRequestsScreen extends StatefulWidget {
  const AdminRequestsScreen({super.key, required this.rso});

  final Rso rso;

  static Route<bool> route(Rso rso) =>
      MaterialPageRoute<bool>(builder: (_) => AdminRequestsScreen(rso: rso));

  @override
  State<AdminRequestsScreen> createState() => _AdminRequestsScreenState();
}

class _AdminRequestsScreenState extends State<AdminRequestsScreen> {
  List<AdminRequest>? _requests;
  String? _error;

  /// The request being approved or declined, so only its buttons spin.
  int? _deciding;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final requests = await context.read<AppServices>().groups.adminRequests(
        widget.rso.id,
      );
      if (mounted) setState(() => _requests = requests);
    } on ApiException catch (e) {
      if (!mounted) return;
      reportError(context, e, screen: Screens.adminRequests);
      setState(() => _error = e.message);
    }
  }

  Future<void> _decide(AdminRequest request, {required bool approve}) async {
    final online = await ensureOnline(
      context,
      title: 'Answering needs a connection',
      message:
          '${request.requesterName} is notified of your answer through '
          "SENECApp. Try again when you're back online.",
    );
    if (!online || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deciding = request.id);
    try {
      await context.read<AppServices>().groups.decideAdminRequest(
        widget.rso.id,
        request.id,
        approve: approve,
      );
      if (!mounted) return;
      _changed = true;
      setState(
        () => _requests = [
          for (final r in _requests ?? const <AdminRequest>[])
            if (r.id != request.id) r,
        ],
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? '${request.requesterName} is now an admin.'
                : 'Request from ${request.requesterName} declined.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      reportError(context, e, screen: Screens.adminRequests);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      // Someone else may have answered it already.
      _load();
    } finally {
      if (mounted) setState(() => _deciding = null);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) Navigator.of(context).pop(_changed);
    },
    child: TrackScreen(
      name: Screens.adminRequests,
      ready: _requests != null || _error != null,
      child: _buildScreen(context),
    ),
  );

  Widget _buildScreen(BuildContext context) {
    final requests = _requests;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              kPageGutter,
              12,
              kPageGutter,
              kNavBarClearance,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    size: 36,
                    iconSize: 17,
                    onPressed: () => Navigator.of(context).pop(_changed),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin requests',
                          style: AppTheme.heading(size: 20),
                        ),
                        Text(
                          'Members of ${widget.rso.name} who want to help run '
                          'it. Admins can create events and manage the group.',
                          style: AppTheme.body(
                            size: 12,
                            height: 1.4,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_error case final error?)
                ErrorBlock(
                  message: error,
                  onRetry: _load,
                  offlineMessage:
                      'Requests are always loaded live, so the list is '
                      'never out of date. Open it again when you are online.',
                )
              else if (requests == null)
                const LoadingBlock()
              else if (requests.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'No requests waiting.',
                    textAlign: TextAlign.center,
                    style: AppTheme.body(
                      size: 13,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                )
              else
                for (final request in requests) ...[
                  _RequestCard(
                    request: request,
                    busy: _deciding == request.id,
                    enabled: _deciding == null,
                    onApprove: () => _decide(request, approve: true),
                    onDecline: () => _decide(request, approve: false),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.busy,
    required this.enabled,
    required this.onApprove,
    required this.onDecline,
  });

  final AdminRequest request;
  final bool busy;
  final bool enabled;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.requesterName,
            style: AppTheme.heading(size: 15, weight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            '${request.requesterEmail} · ${Dates.day(request.createdAt)}',
            style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
          ),
          if (request.note case final note?) ...[
            const SizedBox(height: 10),
            Text(
              '"$note"',
              style: AppTheme.body(
                size: 13,
                height: 1.45,
                color: AppColors.bodyForeground,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: PrimaryButton.secondary(
                  label: 'Decline',
                  onPressed: enabled ? onDecline : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(
                  label: 'Approve',
                  busy: busy,
                  onPressed: enabled ? onApprove : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
