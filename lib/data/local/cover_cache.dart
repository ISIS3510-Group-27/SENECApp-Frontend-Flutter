import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../core/assets/asset_catalog.dart';
import '../../core/config/app_config.dart';
import '../models/rso.dart';

/// Group cover photos on disk, so they show offline and aren't downloaded
/// again on every launch.
class CoverCache {
  /// [download] stores one photo (by default in [shared], skipping photos it
  /// already has); tests pass their own.
  CoverCache({Future<void> Function(String url)? download})
    : _download = download ?? _store;

  static Future<void> _store(String url) => shared.getSingleFile(url);

  /// Every upload gets a new URL, so a stored photo is never out of date: 30
  /// days only bounds how long an unseen group's photo takes space. 200 files
  /// (about 150 KB each after the backend's resize) cap it near 30 MB.
  static final shared = CacheManager(
    Config(
      'senecapp_covers',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 200,
    ),
  );

  /// Downloads at a time: enough to finish quickly, few enough not to compete
  /// with what the student is opening.
  static const parallel = 3;

  final Future<void> Function(String url) _download;

  /// The photo [rso] shows from the network, or `null` when it shows bundled
  /// art (or nothing): a photo the group uploaded beats the bundled art.
  static String? urlFor(Rso rso) {
    final url = rso.imageUrl;
    if (url == null) return null;
    final uploaded =
        url.startsWith('/media/') || url.contains('firebasestorage');
    if (!uploaded && AssetCatalog.orgImage(rso.imageSlug) != null) return null;
    return AppConfig.resolveImageUrl(url);
  }

  /// Downloads the covers of [groups] in the background, [parallel] at a
  /// time, so they're on the phone before the student goes offline. Photos
  /// already stored aren't downloaded again. Returns how many are stored.
  ///
  /// Each download is a Future with its own handlers: `then` counts it,
  /// `catchError` lets one failure (a deleted photo, the connection dropping)
  /// not stop the others. The batches are awaited one after another
  /// (async/await), which is what keeps at most [parallel] in flight.
  Future<int> prefetch(Iterable<Rso> groups) async {
    final urls = {for (final rso in groups) ?urlFor(rso)}.toList();
    var stored = 0;
    for (var start = 0; start < urls.length; start += parallel) {
      final batch = urls
          .skip(start)
          .take(parallel)
          .map(
            (url) =>
                _download(url).then((_) => stored++).catchError((Object error) {
                  debugPrint('Cover not stored ($url): $error');
                  return stored;
                }),
          );
      await Future.wait(batch);
    }
    return stored;
  }
}
