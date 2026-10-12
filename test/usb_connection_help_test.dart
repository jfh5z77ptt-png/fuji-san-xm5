import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuji_san/camera/ptp.dart';
import 'package:fuji_san/main.dart';
import 'package:fuji_san/usb_connection_help.dart';

import 'ui_test.dart' show MemoryStore;

void main() {
  testWidgets('iPhone USB guide fits a phone and never opens a camera', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
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
    await tester.tap(find.byTooltip('USB 연결 안내'));
    await tester.pumpAndSettle();
    expect(find.text('USB로 카메라 연결'), findsOneWidget);
    expect(find.textContaining('USB-C to USB-C'), findsOneWidget);
    expect(find.textContaining('Windows 기본 WPD'), findsNothing);
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  test('instructions describe permissions for the current platform', () {
    expect(
      usbConnectionInstructions(TargetPlatform.android),
      contains('USB 접근 권한'),
    );
    expect(usbConnectionInstructions(TargetPlatform.windows), contains('WPD'));
    expect(
      usbConnectionInstructions(TargetPlatform.iOS),
      contains('SUPPLY OFF/COMM ON'),
    );
  });
}
