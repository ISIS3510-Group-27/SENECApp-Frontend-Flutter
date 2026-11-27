import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:senecapp/core/concurrency/cover_compressor.dart';
import 'package:senecapp/data/api/api_client.dart';
import 'package:senecapp/data/local/cover_outbox_store.dart';
import 'package:senecapp/state/cover_outbox.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  const account = 's.arango@uniandes.edu.co';

  Uint8List photo(int width, int height) => Uint8List.fromList(
    img.encodeJpg(img.Image(width: width, height: height), quality: 90),
  );

  group('CoverCompressor', () {
    test('shrinks a large photo to the maximum side and keeps the ratio', () {
      final small = CoverCompressor.shrink(photo(3000, 1500));
      final decoded = img.decodeJpg(small)!;
      expect(decoded.width, CoverCompressor.maxSide);
      expect(decoded.height, 640);
    });

    test('shrinks a tall photo by its height', () {
      final decoded = img.decodeJpg(CoverCompressor.shrink(photo(1000, 2560)))!;
      expect(decoded.height, CoverCompressor.maxSide);
      expect(decoded.width, 500);
    });

    test('keeps the size of a photo that is already small', () {
      final decoded = img.decodeJpg(CoverCompressor.shrink(photo(800, 600)))!;
      expect(decoded.width, 800);
      expect(decoded.height, 600);
    });

    test('runs on a background isolate', () async {
      final small = await CoverCompressor.compress(photo(2000, 1000));
      expect(img.decodeJpg(small)!.width, CoverCompressor.maxSide);
    });

    test('returns bytes it cannot decode untouched', () {
      final junk = Uint8List.fromList([1, 2, 3]);
      expect(CoverCompressor.shrink(junk), junk);
    });
  });

  group('stores', () {
    Future<void> exercise(CoverOutboxStore store) async {
      await store.put(account, 1, Uint8List.fromList([1]));
      await store.put(account, 2, Uint8List.fromList([2]));
      await store.put(account, 1, Uint8List.fromList([3]));
      await store.put('other@uniandes.edu.co', 9, Uint8List.fromList([9]));

      final pending = await store.pending(' ${account.toUpperCase()} ');
      expect(pending.map((c) => c.groupId).toSet(), {1, 2});
      expect((await store.read(account, 1))!.bytes, [3]);
      expect(await store.read(account, 9), isNull);

      await store.remove(account, 1);
      expect(await store.read(account, 1), isNull);
      expect((await store.pending(account)).single.groupId, 2);
    }

    test('memory store keeps one cover per account and group', () async {
      await exercise(MemoryCoverOutboxStore());
    });

    test('sqlite store keeps one cover per account and group', () async {
      final directory = await Directory.systemTemp.createTemp('senecapp_cov_');
      final store = SqliteCoverOutboxStore(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}/cover_outbox.db',
      );
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      await exercise(store);
    });

    test('sqlite store survives closing the app', () async {
      final directory = await Directory.systemTemp.createTemp('senecapp_cov_');
      final location = '${directory.path}/cover_outbox.db';
      final first = SqliteCoverOutboxStore(
        factory: databaseFactoryFfi,
        databasePath: location,
      );
      await first.put(account, 4, Uint8List.fromList([4, 4]));
      await first.close();

      final second = SqliteCoverOutboxStore(
        factory: databaseFactoryFfi,
        databasePath: location,
      );
      addTearDown(() async {
        await second.close();
        await directory.delete(recursive: true);
      });
      expect((await second.read(account, 4))!.bytes, [4, 4]);
    });
  });

  group('CoverOutbox', () {
    late MemoryCoverOutboxStore store;
    late StreamController<void> reconnected;
    late List<String> uploads;
    Object? failure;
    late CoverOutbox outbox;

    setUp(() {
      store = MemoryCoverOutboxStore();
      reconnected = StreamController<void>.broadcast();
      uploads = [];
      failure = null;
      outbox = CoverOutbox(
        store: store,
        account: account,
        reconnected: reconnected.stream,
        compress: (bytes) async => bytes,
        upload: (groupId, bytes) async {
          final error = failure;
          if (error != null) throw error;
          uploads.add('$groupId:${bytes.join(",")}');
        },
      );
      addTearDown(() async {
        outbox.dispose();
        await reconnected.close();
      });
    });

    test('uploads right away when there is a connection', () async {
      final result = await outbox.submit(1, Uint8List.fromList([1, 2]));
      expect(result!.uploaded, isTrue);
      expect(uploads, ['1:1,2']);
      expect(outbox.hasPending(1), isFalse);
      expect(await store.pending(account), isEmpty);
    });

    test('keeps the photo while offline and sends it on reconnect', () async {
      await outbox.start();
      failure = const ApiException(null, 'No connection');
      final result = await outbox.submit(1, Uint8List.fromList([7]));
      expect(result, isNull);
      expect(outbox.hasPending(1), isTrue);
      expect(await store.pending(account), hasLength(1));
      expect(uploads, isEmpty);

      failure = null;
      final sent = outbox.results.first;
      reconnected.add(null);
      final done = await sent;

      expect(done.groupId, 1);
      expect(done.uploaded, isTrue);
      expect(uploads, ['1:7']);
      expect(outbox.hasPending(1), isFalse);
      expect(await store.pending(account), isEmpty);
    });

    test('a server error keeps the photo for later too', () async {
      failure = const ApiException(503, 'Down');
      expect(await outbox.submit(2, Uint8List.fromList([5])), isNull);
      expect(outbox.hasPending(2), isTrue);
    });

    test('a refused photo is dropped and reported', () async {
      failure = const ApiException(422, 'That photo is not valid.');
      final result = await outbox.submit(1, Uint8List.fromList([5]));
      expect(result!.uploaded, isFalse);
      expect(result.message, 'That photo is not valid.');
      expect(outbox.hasPending(1), isFalse);
      expect(await store.pending(account), isEmpty);
    });

    test('photos saved before the app closed are sent on start', () async {
      await store.put(account, 3, Uint8List.fromList([3, 3]));
      final sent = outbox.results.first;
      await outbox.start();
      expect((await sent).groupId, 3);
      expect(uploads, ['3:3,3']);
    });

    test('a newer photo is not lost when an older one finishes', () async {
      final gate = Completer<void>();
      final slow = CoverOutbox(
        store: store,
        account: account,
        reconnected: const Stream.empty(),
        compress: (bytes) async => bytes,
        upload: (groupId, bytes) async {
          uploads.add('$groupId:${bytes.join(",")}');
          if (uploads.length == 1) await gate.future;
        },
      );
      addTearDown(slow.dispose);

      final first = slow.submit(1, Uint8List.fromList([1]));
      await Future<void>.delayed(Duration.zero);
      await store.put(account, 1, Uint8List.fromList([2]));
      gate.complete();
      await first;

      expect((await store.read(account, 1))!.bytes, [2]);
    });
  });
}
