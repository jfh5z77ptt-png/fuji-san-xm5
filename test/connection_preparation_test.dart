import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuji_san/camera/camera.dart';
import 'package:fuji_san/camera/ptp.dart';
import 'package:fuji_san/main.dart';
import 'package:fuji_san/domain/recipe.dart';

import 'slot_navigation_test.dart' show BackupStore;
import 'xm5_test.dart' show Xm5Fixture;

class PreparationStore extends BackupStore {
  bool failBackup = false;
  @override
  Future<String> backup(
    CameraIdentity identity,
    List<Snapshot> snapshots,
  ) async {
    if (failBackup) throw FileSystemTestFailure();
    return super.backup(identity, snapshots);
  }
}

class FileSystemTestFailure extends StateError {
  FileSystemTestFailure() : super('disk full');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('X-M5 firmware prepares without changing a bank or recipe', () async {
    final fixture = Xm5Fixture(firmware: '1.20')..descriptorsUnavailable = true;
    final camera = FujiCamera(fixture);
    await camera.inspect();
    await camera.validateAccess();
    expect(fixture.selectedSlots, isEmpty);
    expect(fixture.written, isEmpty);
    expect(
      fixture.commands.where((code) => code == 0x1014).length,
      settings.length + 2,
    );
  });
  test(
    'unverified X-M5 firmware validates model values without slot selection',
    () async {
      final fixture = Xm5Fixture(firmware: '9.99')
        ..descriptorsUnavailable = true;
      final camera = FujiCamera(fixture);
      await camera.inspect();
      await camera.validateAccess();
      expect(fixture.selectedSlots, isEmpty);
      expect(fixture.written, isEmpty);
    },
  );

  for (final scenario in ['ready', 'descriptor', 'disk', 'xt5-readonly']) {
    testWidgets('automatic preparation: $scenario', (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async => tester.pumpWidget(const SizedBox()));
      final fixture = Xm5Fixture(
        model: scenario == 'xt5-readonly' ? 'X-T5' : 'X-M5',
        firmware: scenario == 'xt5-readonly' ? '4.31' : '9.99',
        rejectDescriptor: scenario == 'descriptor' ? 0xd18c : null,
        descriptorErrorCode: 0x200f,
      )..descriptorsUnavailable = true;
      if (scenario == 'xt5-readonly') {
        fixture.slots[fixture.selected]![0xd195] = u16(7);
      }
      final store = PreparationStore()..failBackup = scenario == 'disk';
      if (scenario == 'xt5-readonly') {
        final recipe = Recipe.fresh();
        await store.save([recipe], {4: recipe.id});
      }
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final nativeCalls = <String>[];
      messenger.setMockMethodCallHandler(NativeTransport.channel, (call) async {
        nativeCalls.add(call.method);
        if (call.method == 'discover') {
          return [
            {'id': 'wpd:test', 'name': 'X-M5'},
          ];
        }
        if (call.method == 'connect') return {'managedSession': true};
        if (call.method == 'disconnect') return null;
        final args = call.arguments as Map;
        final packet = Packet.decode(args['command'] as Uint8List);
        final bytes = ByteData.sublistView(packet.payload);
        final params = [
          for (var i = 0; i < bytes.lengthInBytes; i += 4)
            bytes.getUint32(i, Endian.little),
        ];
        var code = 0x2001;
        var data = Uint8List(0);
        try {
          data = await fixture.command(
            packet.code,
            params: params,
            outgoing: args['outgoing'] as Uint8List?,
          );
        } on PtpResponseException catch (error) {
          code = error.code;
        }
        return {
          'data': data,
          'response': Packet(
            3,
            code,
            packet.transaction,
            Uint8List(0),
          ).encode(),
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(NativeTransport.channel, null),
      );
      await tester.pumpWidget(FujiSanApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('카메라 연결'));
      await tester.pumpAndSettle();
      expect(find.text('연결할 카메라'), findsNothing);
      expect(fixture.written, isEmpty);
      if (scenario == 'xt5-readonly') {
        expect(store.backupsSaved, 1);
        expect(find.text('X-T5 읽기 전용'), findsOneWidget);
        expect(fixture.selectedSlots, isEmpty);
        expect(fixture.written, isEmpty);
        await tester.scrollUntilVisible(
          find.text('Original 4'),
          150,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('camera-kit')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(find.text('Original 4'));
        await tester.pumpAndSettle();
        expect(find.textContaining('미확인 원시값 7'), findsOneWidget);
        expect(find.text('카메라에 저장'), findsNothing);
        await tester.tap(find.text('닫기'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('1개 슬롯 일괄 적용'),
          150,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('camera-kit')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(find.text('1개 슬롯 일괄 적용'));
        await tester.pumpAndSettle();
        expect(find.text('X-T5 전송 검증이 필요합니다'), findsOneWidget);
        expect(fixture.selectedSlots, isEmpty);
        expect(fixture.written, isEmpty);
        await tester.tap(find.text('취소'));
        await tester.pumpAndSettle();
      } else if (scenario == 'ready') {
        expect(store.backupsSaved, 1);
        expect(find.text('X-M5 준비 완료'), findsOneWidget);
        expect(fixture.selected, 4);
        // Periodic verification reads a property without writing a bank.
        final selections = fixture.selectedSlots.length;
        await tester.pump(const Duration(seconds: 31));
        await tester.pumpAndSettle();
        expect(fixture.selectedSlots.length, selections);
      } else {
        expect(store.backupsSaved, 0);
        expect(find.text('X-M5 준비 완료'), findsNothing);
        expect(nativeCalls, contains('disconnect'));
        expect(
          find.text(
            scenario == 'descriptor'
                ? '설정 범위 조회를 카메라가 거부했습니다'
                : '백업 파일을 저장하지 못했습니다',
          ),
          findsOneWidget,
        );
        if (scenario == 'descriptor') expect(fixture.selectedSlots, isEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
