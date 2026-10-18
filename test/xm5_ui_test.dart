import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuji_san/domain/recipe.dart';
import 'package:fuji_san/main.dart';
import 'package:fuji_san/camera/ptp.dart';

import 'ui_test.dart' show MemoryStore;

void main() {
  testWidgets('slot probe cancellation sends no native camera calls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(NativeTransport.channel, (call) async {
      calls.add(call.method);
      return <dynamic>[];
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(NativeTransport.channel, null),
    );
    await tester.pumpWidget(FujiSanApp(store: MemoryStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('X-M5 (실험적)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('X-M5 슬롯 전환 진단'));
    await tester.pumpAndSettle();
    expect(find.textContaining('USB의 슬롯 선택값 1~4'), findsOneWidget);
    expect(find.text('진단 실행'), findsOneWidget);
    expect(calls, isEmpty);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
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
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('X-T5 (실험적)').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('X-T5 4.31의 USB 슬롯 전환'), findsOneWidget);
      expect(find.text('X-M5 슬롯 전환 진단'), findsNothing);
      expect(find.text('X-T5 슬롯 전환 진단'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('C7'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('camera-kit')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('C7'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('1개 슬롯 일괄 적용'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('camera-kit')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('1개 슬롯 일괄 적용'), findsOneWidget);
      expect((store.data!['slots'] as Map)['7'], recipe.id);
      expect(tester.takeException(), isNull);
    },
  );
}
