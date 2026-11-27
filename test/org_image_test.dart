import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/core/assets/asset_catalog.dart';
import 'package:senecapp/core/theme/app_colors.dart';
import 'package:senecapp/core/widgets/org_image.dart';
import 'package:senecapp/data/models/rso.dart';
import 'package:senecapp/data/models/rso_category.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The bundled photos are only known once the asset manifest is read.
  setUpAll(AssetCatalog.load);

  const tennis = Rso(
    id: 1,
    name: 'Tennis Uniandes',
    category: RsoCategory.sports,
    members: 142,
    description: 'Competitive and recreational tennis for all levels.',
    tags: ['Tennis'],
    color: AppColors.primary,
    verified: true,
  );

  Future<int?> decodedWidth(
    WidgetTester tester, {
    required Size slot,
    double pixelRatio = 3,
  }) async {
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.fromSize(
            size: slot,
            child: const OrgImage(rso: tennis),
          ),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image;
    return provider is ResizeImage ? provider.width : null;
  }

  // Micro-optimization: covers are decoded at the size they are drawn.
  testWidgets('a list tile decodes the cover small, not at 900 px', (
    tester,
  ) async {
    // 56x56 tile at 3x: BoxFit.cover needs 56 * 1.5 * 3 = 252 -> 256 px.
    expect(await decodedWidth(tester, slot: const Size(56, 56)), 256);
  });

  testWidgets('a full-width cover decodes at the screen width', (tester) async {
    // 360x200 at 3x: 1080 px, rounded up to 1088.
    expect(await decodedWidth(tester, slot: const Size(360, 200)), 1088);
  });
}
