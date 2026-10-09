import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuji_san/camera/camera.dart';
import 'package:fuji_san/camera/model.dart';
import 'package:fuji_san/camera/ptp.dart';
import 'package:fuji_san/domain/recipe.dart';

import 'write_verify_test.dart' show CameraFixture;

Uint8List u32(int n) =>
    (ByteData(4)..setUint32(0, n, Endian.little)).buffer.asUint8List();

class Xm5Fixture extends CameraFixture {
  Xm5Fixture({
    this.model = 'X-M5',
    this.missingProperty,
    this.rejectDescriptor,
  });
  final String model;
  final int? missingProperty, rejectDescriptor;
  final commands = <int>[];
  final selectedSlots = <int>[];
  @override
  Future<Uint8List> command(
    int code, {
    List<int> params = const [],
    Uint8List? outgoing,
  }) async {
    commands.add(code);
    if (code == 0x1001) {
      final properties = {0xd18c, 0xd18d, ...settings.map((s) => s.id)}
        ..remove(missingProperty);
      List<int> array(Iterable<int> values) => [
        ...u32(values.length),
        for (final n in values) ...u16(n),
      ];
      return Uint8List.fromList([
        ...u16(100),
        ...u32(0),
        ...u16(100),
        ...ptpString(''),
        ...u16(0),
        ...array([0x1001, 0x1014, 0x1015, 0x1016]),
        ...array([]),
        ...array(properties),
        ...array([]),
        ...array([]),
        ...ptpString('FUJIFILM'),
        ...ptpString(model),
        ...ptpString('1.32'),
        ...ptpString('test-private-serial'),
      ]);
    }
    if (code == 0x1014 && params.first == rejectDescriptor) {
      throw PtpResponseException(0x2002, code);
    }
    if (params.first == 0xd18c) {
      if (code == 0x1014) {
        if (descriptorsUnavailable) throw PtpResponseException(0x2002, code);
        return Uint8List.fromList([
          ...u16(0xd18c),
          ...u16(4),
          1,
          ...u16(1),
          ...u16(selected),
          2,
          ...u16(4),
          for (var i = 1; i <= 4; i++) ...u16(i),
        ]);
      }
      if (code == 0x1016) {
        selectedSlots.add(Reader(outgoing!).read16());
      }
    }
    return super.command(code, params: params, outgoing: outgoing);
  }
}

void main() {
  test('X-M5 profile selects four banks, X100VI keeps seven', () {
    expect(CameraModel.xm5.slots, {1, 2, 3, 4});
    expect(CameraModel.x100vi.slots.length, 7);
    expect(CameraModel.fromName('x-m5'), CameraModel.xm5);
    expect(CameraModel.fromName('X-T5'), isNull);
  });

  test(
    'X-M5 inspect, scan and write preserve selector and other banks',
    () async {
      final fixture = Xm5Fixture();
      final camera = FujiCamera(fixture);
      await camera.inspect();
      final backups = await camera.backup(camera.profile.slots);
      expect(backups.map((s) => s.slot), [1, 2, 3, 4]);
      expect(fixture.written, isEmpty);
      await camera.write(1, Recipe.fresh());
      expect(Reader(fixture.slots[1]![0xd18d]!).string(), 'My Recipe');
      expect(Reader(fixture.slots[2]![0xd18d]!).string(), 'Original 2');
      await camera.restore(backups.first);
      expect(Reader(fixture.slots[1]![0xd18d]!).string(), 'Original 1');
      expect(fixture.selected, 4);
      expect(fixture.selectedSlots.every((slot) => slot <= 4), isTrue);
    },
  );

  test(
    'invalid X-M5 bank rejects entire operation before any USB command',
    () async {
      final fixture = Xm5Fixture();
      final camera = FujiCamera(fixture);
      await camera.inspect();
      fixture.commands.clear();
      await expectLater(camera.backup({1, 5}), throwsRangeError);
      await expectLater(camera.write(7, Recipe.fresh()), throwsRangeError);
      expect(fixture.commands, isEmpty);
    },
  );

  test('X-M5 does not inherit X100VI 1.32 descriptor fallback', () async {
    final fixture = Xm5Fixture()..descriptorsUnavailable = true;
    final camera = FujiCamera(fixture);
    await camera.inspect();
    await expectLater(
      camera.write(1, Recipe.fresh()),
      throwsA(isA<PtpResponseException>()),
    );
    expect(fixture.written, isEmpty);
    expect(fixture.selected, 4);
  });

  test(
    'late descriptor failure blocks every recipe write and restores selector',
    () async {
      final fixture = Xm5Fixture(rejectDescriptor: 0xd18d);
      final camera = FujiCamera(fixture);
      await camera.inspect();
      await expectLater(
        camera.write(1, Recipe.fresh()),
        throwsA(isA<PtpResponseException>()),
      );
      expect(fixture.written, isEmpty);
      expect(fixture.selected, 4);
    },
  );

  test(
    'incomplete X-M5 can be diagnosed without slot or recipe writes',
    () async {
      final fixture = Xm5Fixture(missingProperty: 0xd193);
      final camera = FujiCamera(fixture);
      await expectLater(camera.inspect(), throwsStateError);
      expect(camera.identity, isNull);
      await camera.inspect(requireRecipeProperties: false);
      final report = await camera.probeCapabilities();
      expect(report['model'], 'X-M5');
      expect((report['properties'] as Map).containsKey('d193'), isFalse);
      expect(report.toString(), isNot(contains('test-private-serial')));
      expect(fixture.commands, isNot(contains(0x1016)));
      expect(fixture.selected, 4);
    },
  );

  test('raw write-back diagnostic is unavailable for X-M5', () async {
    final fixture = Xm5Fixture();
    final camera = FujiCamera(fixture);
    await camera.inspect();
    fixture.commands.clear();
    await expectLater(camera.probeWriteBack({1}), throwsStateError);
    expect(fixture.commands, isEmpty);
  });

  test('unsupported model remains rejected', () async {
    final camera = FujiCamera(Xm5Fixture(model: 'X-T5'));
    await expectLater(camera.inspect(), throwsStateError);
    expect(camera.identity, isNull);
  });
}
