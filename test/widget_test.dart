import 'package:diexu/app.dart';
import 'package:diexu/core/providers.dart';
import 'package:diexu/features/outfits/domain/outfit.dart';
import 'package:diexu/features/wardrobe/domain/wardrobe_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptyWardrobe extends WardrobeController {
  @override
  Future<List<WardrobeItem>> build() async => [];
}

class _EmptyOutfits extends OutfitController {
  @override
  Future<List<Outfit>> build() async => [];
}

void main() {
  testWidgets('展示离线衣橱首页与主导航', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeItemsProvider.overrideWith(_EmptyWardrobe.new),
          outfitsProvider.overrideWith(_EmptyOutfits.new),
        ],
        child: const DiexuApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的衣橱'), findsOneWidget);
    expect(find.text('衣橱'), findsOneWidget);
    expect(find.text('搭配'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('从第一件心爱单品开始'), findsOneWidget);
  });
}
