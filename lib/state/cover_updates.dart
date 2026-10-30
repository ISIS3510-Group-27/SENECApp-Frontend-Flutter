import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';

class CoverUpdates extends ChangeNotifier {
  final _urls = <int, String>{};

  String? latest(int groupId) => _urls[groupId];

  void record(int groupId, String? imageUrl) {
    if (imageUrl == null) return;
    final url = AppConfig.resolveImageUrl(imageUrl);
    if (_urls[groupId] == url) return;
    _urls[groupId] = url;
    notifyListeners();
  }
}
