import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuji_san/domain/recipe.dart';
import 'package:fuji_san/main.dart';

import 'ui_test.dart' show MemoryStore;

void main() {
  testWidgets(
    'switch to X-M5 shows four banks and preserves hidden assignments',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final recipe = Recipe.fresh();
      final store = MemoryStore();
      await store.save([recipe], {7: recipe.id});
      await tester.pumpWidget(FujiSanApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('C7'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('X-M5 (실험적)').last);
      await tester.pumpAndSettle();
      expect(find.text('C4'), findsOneWidget);
      expect(find.text('C5'), findsNothing);
      expect(find.text('C7'), findsNothing);
      expect(find.text('0개 슬롯 일괄 적용'), findsOneWidget);
      expect((store.data!['slots'] as Map)['7'], recipe.id);
      expect(tester.takeException(), isNull);
    },
  );
}
