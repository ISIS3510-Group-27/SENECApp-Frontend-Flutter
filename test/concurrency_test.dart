import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/core/concurrency/background_json.dart';
import 'package:senecapp/core/theme/app_colors.dart';
import 'package:senecapp/data/local/cover_cache.dart';
import 'package:senecapp/data/models/rso.dart';
import 'package:senecapp/data/models/rso_category.dart';

/// Multi-threading: JSON decoded on a background isolate, and covers
/// downloaded concurrently in the background.
void main() {
  group('BackgroundJson', () {
    List<Map<String, Object?>> events(int count) => [
      for (var i = 0; i < count; i++)
        {'id': i, 'title': 'Event $i', 'description': 'x' * 200},
    ];

    test('small and large answers decode the same way', () async {
      for (final count in [2, 400]) {
        final bytes = Uint8List.fromList(
          utf8.encode(jsonEncode({'items': events(count)})),
        );
        // 400 events cross the threshold: that one runs on another isolate.
        expect(bytes.length >= BackgroundJson.threshold, count == 400);

        final decoded = await BackgroundJson.decodeBytes(bytes);
        expect(decoded, {'items': events(count)});
      }
    });

    test('an empty body is null', () async {
      expect(await BackgroundJson.decodeBytes(Uint8List(0)), isNull);
    });

    test('rows round-trip through encodeAll and decodeAll', () async {
      final values = events(300);
      final texts = await BackgroundJson.encodeAll(values);
      expect(await BackgroundJson.decodeAll(texts), values);
    });
  });

  group('CoverCache', () {
    Rso group(int id, String? imageUrl) => Rso(
      id: id,
      name: 'Group $id',
      category: RsoCategory.sports,
      members: 10,
      description: '',
      tags: const [],
      color: AppColors.primary,
      verified: false,
      imageUrl: imageUrl,
    );

    test('only photos shown from the network are downloaded', () {
      expect(CoverCache.urlFor(group(1, null)), isNull);
      expect(
        CoverCache.urlFor(group(2, '/media/groups/2/cover-ab.jpg')),
        endsWith('/media/groups/2/cover-ab.jpg'),
      );
    });

    test('downloads a few at a time, and one failure stops nothing', () async {
      final downloads = _FakeDownloads(failing: {'/media/3.jpg'});
      final cache = CoverCache(download: downloads.download);

      final stored = await cache.prefetch([
        for (var id = 1; id <= 7; id++) group(id, '/media/$id.jpg'),
        group(8, '/media/1.jpg'), // Same photo: downloaded once.
      ]);

      expect(stored, 6);
      expect(downloads.requested, hasLength(7));
      expect(downloads.mostAtOnce, CoverCache.parallel);
    });
  });
}

/// Pretends to download, slowly enough that overlapping downloads show.
class _FakeDownloads {
  _FakeDownloads({this.failing = const {}});

  final Set<String> failing;
  final List<String> requested = [];
  int _inFlight = 0;
  int mostAtOnce = 0;

  Future<void> download(String url) async {
    requested.add(url);
    _inFlight++;
    if (_inFlight > mostAtOnce) mostAtOnce = _inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _inFlight--;
    if (failing.any(url.endsWith)) throw Exception('404 for $url');
  }
}
