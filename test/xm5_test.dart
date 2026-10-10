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
    this.firmware = '1.32',
    this.missingProperty,
    this.rejectDescriptor,
    this.descriptorErrorCode = 0x2002,
  });
  final String model, firmware;
  final int? missingProperty, rejectDescriptor;
  final int descriptorErrorCode;
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
        ...ptpString(firmware),
        ...ptpString('test-private-serial'),
      ]);
    }
    if (code == 0x1014 && params.first == rejectDescriptor) {
      throw PtpResponseException(descriptorErrorCode, code);
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
          ...u16(CameraModel.fromName(model)?.slotCount ?? 4),
          for (
            var i = 1;
            i <= (CameraModel.fromName(model)?.slotCount ?? 4);
            i++
          )
            ...u16(i),
        ]);
      }
      if (code == 0x1016) {
        selectedSlots.add(Reader(outgoing!).read16());
      }
    }
    return super.command(code, params: params, outgoing: outgoing);
  }
}

class Xm5ProbeFixture extends Xm5Fixture {
  Xm5ProbeFixture({
    this.ignoreCandidate,
    this.failReadAt,
    this.failRestoration = false,
    this.malformedSelector = false,
  }) : super(firmware: '1.20') {
    selected = 2;
    descriptorsUnavailable = true;
  }
  final int? ignoreCandidate, failReadAt;
  final bool failRestoration, malformedSelector;
  final selectorWriteAttempts = <int>[];

  @override
  Future<Uint8List> command(
    int code, {
    List<int> params = const [],
    Uint8List? outgoing,
  }) async {
    if (code == 0x1015 && params.first == 0xd18c && malformedSelector) {
      return Uint8List.fromList([2]);
    }
    if (code == 0x1015 && params.first == 0xd192 && selected == failReadAt) {
      throw PtpResponseException(0x2002, code);
    }
    if (code == 0x1016 && params.first == 0xd18c) {
      final candidate = Reader(outgoing!).read16();
      selectorWriteAttempts.add(candidate);
      if (candidate == ignoreCandidate) return Uint8List(0);
      if (failRestoration && selectorWriteAttempts.length > 4) {
        throw PtpResponseException(0x2002, code);
      }
    }
    return super.command(code, params: params, outgoing: outgoing);
  }
}

class Xm5ObservedFixture extends Xm5Fixture {
  Xm5ObservedFixture() : super(firmware: '1.20') {
    selected = 2;
    descriptorsUnavailable = true;
    final observed = <int, int>{
      0xd192: 11,
      0xd191: 0,
      0xd190: 400,
      0xd193: 0,
      0xd194: 0,
      0xd195: 6,
      0xd196: 2,
      0xd197: 2,
      0xd198: 1,
      0xd199: 32775,
      0xd19c: 4400,
      0xd19a: 0,
      0xd19b: 1,
      0xd19d: -10,
      0xd19e: -10,
      0xd19f: 20,
      0xd1a0: 0,
      0xd1a1: 20480,
      0xd1a2: 0,
    };
    for (final e in observed.entries) {
      slots[1]![e.key] = u16(e.value);
    }
    for (var slot = 2; slot <= 4; slot++) {
      slots[slot]![0xd192] = u16(1);
      slots[slot]![0xd195] = u16(6);
      slots[slot]![0xd19c] = u16(10000);
    }
  }

  @override
  Future<Uint8List> command(
    int code, {
    List<int> params = const [],
    Uint8List? outgoing,
  }) async {
    final value = await super.command(code, params: params, outgoing: outgoing);
    if (code == 0x1015 &&
        params.first == 0xd195 &&
        Reader(value).read16() == 1) {
      return u16(6);
    }
    return value;
  }
}

void main() {
  test(
    'X-T5 scans seven banks and restores one verified bank without affecting others',
    () async {
      final fixture = Xm5Fixture(model: 'X-T5', firmware: 'test');
      final camera = FujiCamera(fixture);
      await camera.inspect();
      expect(camera.profile, CameraModel.xt5);
      final snapshots = await camera.backup(camera.profile.slots);
      expect(snapshots.map((s) => s.slot), [1, 2, 3, 4, 5, 6, 7]);
      expect(fixture.written, isEmpty);
      await camera.write(7, Recipe.fresh());
      expect(Reader(fixture.slots[7]![0xd18d]!).string(), 'My Recipe');
      expect(Reader(fixture.slots[6]![0xd18d]!).string(), 'Original 6');
      await camera.restore(snapshots.last);
      expect(Reader(fixture.slots[7]![0xd18d]!).string(), 'Original 7');
      expect(fixture.selected, 4);
      fixture.commands.clear();
      await expectLater(camera.write(8, Recipe.fresh()), throwsRangeError);
      expect(fixture.commands, isEmpty);
    },
  );
  test('X-T5 never inherits another model descriptor exception', () async {
    for (final firmware in ['1.20', '1.32', 'test']) {
      final fixture = Xm5Fixture(model: 'X-T5', firmware: firmware)
        ..descriptorsUnavailable = true;
      final camera = FujiCamera(fixture);
      await camera.inspect();
      await expectLater(
        camera.backup({7}),
        throwsA(isA<PtpResponseException>()),
      );
      await expectLater(
        camera.write(7, Recipe.fresh()),
        throwsA(isA<PtpResponseException>()),
      );
      expect(fixture.selectedSlots, isEmpty);
      expect(fixture.written, isEmpty);
    }
  });
  test(
    'X-T5 capability inspection remains read-only with missing properties',
    () async {
      final fixture = Xm5Fixture(
        model: 'X-T5',
        firmware: 'test',
        missingProperty: 0xd18d,
      )..descriptorsUnavailable = true;
      final camera = FujiCamera(fixture);
      await camera.inspect(requireRecipeProperties: false);
      final report = await camera.probeCapabilities();
      expect(report['model'], 'X-T5');
      expect(report['slotCount'], 7);
      expect(report['recipeWrites'], false);
      expect(report['slotSelectionWrites'], false);
      expect(fixture.commands, isNot(contains(0x1016)));
    },
  );
  test(
    'X-M5 1.20 observed values scan, write and restore with exact descriptor fallback',
    () async {
      final fixture = Xm5ObservedFixture();
      final camera = FujiCamera(fixture);
      await camera.inspect();
      final backup = await camera.backup(camera.profile.slots);
      expect(backup.map((s) => s.slot), [1, 2, 3, 4]);
      expect(backup.first.values[0xd192], 11);
      expect(backup.first.values[0xd190], 400);
      expect(backup.first.values[0xd199], 32775);
      expect(backup.first.values[0xd19c], 4400);
      expect(backup.first.values[0xd19d], -10);
      expect(backup.first.values[0xd1a1], 20480);
      expect(fixture.written, isEmpty);
      await camera.write(4, Recipe.fresh());
      expect(Reader(fixture.slots[4]![0xd192]!).read16(), 11);
      await camera.restore(backup.last);
      expect((await camera.backup({4})).single.toJson(), backup.last.toJson());
      expect((await camera.backup({1})).single.toJson(), backup.first.toJson());
      expect(fixture.selected, 2);
      expect(fixture.written, isNot(contains(0xd1a5)));
      expect(fixture.selectedSlots.every((s) => s >= 1 && s <= 4), isTrue);
    },
  );

  test(
    'X-M5 1.20 single-field edit saves backup before write and preserves other fields',
    () async {
      final fixture = Xm5ObservedFixture();
      final camera = FujiCamera(fixture);
      await camera.inspect();
      final original = (await camera.backup({4})).single;
      var saved = false;
      await camera.editSlot(
        original,
        SlotEdit(original.rawName, {...original.values, 0xd19f: 10}),
        (snapshots) async {
          expect(fixture.written, isEmpty);
          expect(snapshots.single.toJson(), original.toJson());
          saved = true;
        },
      );
      expect(saved, isTrue);
      expect(fixture.written, [0xd19f]);
      final changed = (await camera.backup({4})).single;
      expect(changed.values[0xd19f], 10);
      for (final e in original.properties.entries) {
        if (e.key != 0xd19f) expect(changed.properties[e.key], e.value);
      }
      expect(fixture.selected, 2);
    },
  );

  test(
    'X-M5 fallback does not mask a different descriptor error or new firmware',
    () async {
      final wrongError = Xm5Fixture(
        firmware: '1.20',
        rejectDescriptor: 0xd18c,
        descriptorErrorCode: 0x200f,
      );
      final camera = FujiCamera(wrongError);
      await camera.inspect();
      await expectLater(
        camera.backup({1}),
        throwsA(isA<PtpResponseException>()),
      );
      expect(wrongError.selectedSlots, isEmpty);
      final unknown = Xm5Fixture(firmware: '1.21')
        ..descriptorsUnavailable = true;
      final other = FujiCamera(unknown);
      await other.inspect();
      await expectLater(
        other.backup({1}),
        throwsA(isA<PtpResponseException>()),
      );
      await expectLater(
        other.write(1, Recipe.fresh()),
        throwsA(isA<PtpResponseException>()),
      );
      expect(unknown.selectedSlots, isEmpty);
      expect(unknown.written, isEmpty);
    },
  );

  test(
    'unrestorable X-M5 snapshot and invalid requested bank cannot write a recipe',
    () async {
      final fixture = Xm5ObservedFixture();
      final camera = FujiCamera(fixture);
      await camera.inspect();
      final original = (await camera.backup({4})).single;
      final invalid = Snapshot(4, {...original.properties, 0xd1a2: u16(500)});
      fixture.commands.clear();
      await expectLater(camera.restore(invalid), throwsStateError);
      await expectLater(camera.write(5, Recipe.fresh()), throwsRangeError);
      expect(fixture.commands, isEmpty);
      expect(fixture.written, isEmpty);
      fixture.slots[4]![0xd1a2] = u16(500);
      await expectLater(camera.backup({4}), throwsStateError);
      expect(fixture.written, isEmpty);
      expect(fixture.selected, 2);
    },
  );
  test('X-M5 profile selects four banks, X100VI keeps seven', () {
    expect(CameraModel.xm5.slots, {1, 2, 3, 4});
    expect(CameraModel.x100vi.slots.length, 7);
    expect(CameraModel.fromName('x-m5'), CameraModel.xm5);
    expect(CameraModel.fromName(' x-t5 '), CameraModel.xt5);
    expect(CameraModel.xt5.slots, {1, 2, 3, 4, 5, 6, 7});
    expect(CameraModel.fromName('X-T4'), isNull);
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
    expect(fixture.selectedSlots, isEmpty);
    await expectLater(
      camera.backup({1, 2, 3, 4}),
      throwsA(isA<PtpResponseException>()),
    );
    expect(fixture.selectedSlots, isEmpty);
  });

  test(
    'X-M5 1.20 slot probe works without descriptors and writes only selector',
    () async {
      final fixture = Xm5ProbeFixture();
      final camera = FujiCamera(fixture);
      await camera.inspect();
      final before = {
        for (final e in fixture.slots.entries)
          e.key: {for (final p in e.value.entries) p.key: p.value.toList()},
      };
      final report = await camera.probeXm5Slots();
      expect(report['success'], isTrue);
      expect(report['recipeWrites'], isFalse);
      expect(report['slotSelectionWrites'], isTrue);
      expect(report['physicalCMappingVerified'], isFalse);
      expect(report['originalSelectorRestored'], isTrue);
      expect(report['originalRecipeFieldsUnchanged'], isTrue);
      expect(report['distinctRecipeSignatures'], 4);
      expect(fixture.selectorWriteAttempts, [1, 2, 3, 4, 2]);
      expect(fixture.written, isEmpty);
      expect(fixture.selected, 2);
      expect(fixture.commands, isNot(contains(0x1014)));
      expect(report.toString(), isNot(contains('Original')));
      expect(report.toString(), isNot(contains('test-private-serial')));
      expect(fixture.slots, before);
    },
  );

  test('slot probe stops on ignored selection and restores original', () async {
    final fixture = Xm5ProbeFixture(ignoreCandidate: 1);
    final camera = FujiCamera(fixture);
    await camera.inspect();
    final report = await camera.probeXm5Slots();
    expect(report['success'], isFalse);
    expect(report['error'], contains('읽기 검증 실패'));
    expect(report['originalSelectorRestored'], isTrue);
    expect(fixture.selectorWriteAttempts, [1, 2]);
    expect(fixture.selected, 2);
    expect(fixture.written, isEmpty);
  });

  test(
    'slot probe preserves partial report and restores after property read failure',
    () async {
      final fixture = Xm5ProbeFixture(failReadAt: 3);
      final camera = FujiCamera(fixture);
      await camera.inspect();
      final report = await camera.probeXm5Slots();
      expect(report['success'], isFalse);
      expect((report['candidateSelectors'] as List).length, 3);
      expect(report['originalSelectorRestored'], isTrue);
      expect(report['originalRecipeFieldsUnchanged'], isTrue);
      expect(fixture.selectorWriteAttempts, [1, 2, 3, 2]);
      expect(fixture.selected, 2);
      expect(fixture.written, isEmpty);
    },
  );

  test('slot probe explicitly reports restoration failure', () async {
    final fixture = Xm5ProbeFixture(failRestoration: true);
    final camera = FujiCamera(fixture);
    await camera.inspect();
    final report = await camera.probeXm5Slots();
    expect(report['success'], isFalse);
    expect(report['originalSelectorRestored'], isFalse);
    expect(report['restoreError'], contains('0x2002'));
    expect(fixture.selected, 4);
    expect(fixture.written, isEmpty);
  });

  test(
    'slot probe rejects unknown firmware and malformed original without writes',
    () async {
      final unknown = Xm5Fixture(firmware: '1.21');
      final camera = FujiCamera(unknown);
      await camera.inspect();
      unknown.commands.clear();
      await expectLater(camera.probeXm5Slots(), throwsStateError);
      expect(unknown.commands, isEmpty);
      final malformed = Xm5ProbeFixture(malformedSelector: true);
      final other = FujiCamera(malformed);
      await other.inspect();
      await expectLater(other.probeXm5Slots(), throwsStateError);
      expect(malformed.selectorWriteAttempts, isEmpty);
      final outOfRange = Xm5ProbeFixture()..selected = 0;
      final third = FujiCamera(outOfRange);
      await third.inspect();
      await expectLater(third.probeXm5Slots(), throwsRangeError);
      expect(outOfRange.selectorWriteAttempts, isEmpty);
    },
  );

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
    final camera = FujiCamera(Xm5Fixture(model: 'X-T4'));
    await expectLater(camera.inspect(), throwsStateError);
    expect(camera.identity, isNull);
  });
}
