import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuji_san/camera/camera.dart';
import 'package:fuji_san/camera/ptp.dart';
import 'package:fuji_san/domain/recipe.dart';

import 'xm5_test.dart' show Xm5Fixture;

class Xt5ObservedFixture extends Xm5Fixture {
  Xt5ObservedFixture({
    this.ignoreCandidate,
    this.failReadAt,
    this.changeGrainOnColor = false,
    super.firmware = '4.31',
  }) : super(model: 'X-T5') {
    selected = 1;
    descriptorsUnavailable = true;
    final observed = <int, int>{
      0xd192: 11,
      0xd191: 0,
      0xd190: 400,
      0xd193: 0,
      0xd194: 0,
      0xd195: 7,
      0xd196: 2,
      0xd197: 2,
      0xd198: 2,
      0xd199: 32800,
      0xd19c: 10000,
      0xd19a: 0,
      0xd19b: -1,
      0xd19d: -5,
      0xd19e: 5,
      0xd19f: 20,
      0xd1a0: 0,
      0xd1a1: 28672,
      0xd1a2: 0,
    };
    for (final e in observed.entries) {
      slots[1]![e.key] = u16(e.value);
    }
    for (var slot = 2; slot <= 7; slot++) {
      slots[slot]![0xd18d] = ptpString('Original default');
      slots[slot]![0xd192] = u16(1);
      slots[slot]![0xd195] = u16(6);
      slots[slot]![0xd19c] = u16(10000);
    }
  }
  final int? ignoreCandidate, failReadAt;
  final bool changeGrainOnColor;
  @override
  Future<Uint8List> command(
    int code, {
    List<int> params = const [],
    Uint8List? outgoing,
  }) async {
    if (code == 0x1016 &&
        params.first == 0xd18c &&
        Reader(outgoing!).read16() == ignoreCandidate) {
      return Future.value(Uint8List(0));
    }
    if (code == 0x1015 && params.first == 0xd192 && selected == failReadAt) {
      throw PtpResponseException(0x2002, code);
    }
    final value = await super.command(code, params: params, outgoing: outgoing);
    if (changeGrainOnColor && code == 0x1016 && params.first == 0xd19f) {
      slots[selected]![0xd195] = u16(99);
    }
    return value;
  }
}

void main() {
  test(
    'X-T5 current bank read preserves unknown grain and issues no descriptor or writes',
    () async {
      final fixture = Xt5ObservedFixture();
      final camera = FujiCamera(fixture);
      await camera.inspect();
      fixture.commands.clear();
      final snapshot = await camera.readCurrentSlot();
      expect(snapshot.values[0xd195], 7);
      expect(snapshot.values[0xd19b], -1);
      expect(snapshot.values[0xd19d], -5);
      expect(snapshot.slot, 1);
      expect(fixture.commands.every((code) => code == 0x1015), true);
      expect(fixture.selectedSlots, isEmpty);
      expect(fixture.written, isEmpty);
    },
  );
  test(
    'X-T5 explicit seven-bank diagnostic restores selection and all recipe bytes',
    () async {
      final fixture = Xt5ObservedFixture();
      final before = fixture.slots.toString();
      final camera = FujiCamera(fixture);
      await camera.inspect();
      final result = await camera.probeXt5Slots();
      expect(result['success'], true);
      expect(result['recipeWrites'], false);
      expect(result['slotSelectionWrites'], true);
      expect(result['physicalCMappingVerified'], false);
      expect(result['originalSelectorRestored'], true);
      expect(result['originalRecipeFieldsUnchanged'], true);
      expect(fixture.selectedSlots, [1, 2, 3, 4, 5, 6, 7, 1]);
      expect(fixture.written, isEmpty);
      expect(fixture.slots.toString(), before);
    },
  );
  test('X-T5 4.31 prepares without any setting or selector writes', () async {
    final fixture = Xt5ObservedFixture();
    final camera = FujiCamera(fixture);
    await camera.inspect();
    await camera.validateAccess();
    expect(camera.preservesGrain, true);
    expect(fixture.selectedSlots, isEmpty);
    expect(fixture.written, isEmpty);
  });

  test(
    'X-T5 backup, batch apply, edit and restore never write grain',
    () async {
      final fixture = Xt5ObservedFixture();
      final camera = FujiCamera(fixture);
      await camera.inspect();
      await camera.validateAccess();
      final originals = await camera.backup(camera.profile.slots);
      expect(originals.map((s) => s.values[0xd195]), [7, 6, 6, 6, 6, 6, 6]);
      final untouched = fixture.slots[2].toString();
      final recipe = Recipe(
        id: 'test',
        name: 'Test',
        cameraName: 'Test',
        values: {...Recipe.fresh().values, 0xd195: 5, 0xd19f: 30},
      );
      await camera.validatePlan({1: recipe});
      var saved = false;
      await BatchWriter(camera).apply({1: recipe}, (snapshots) async {
        expect(fixture.written, isEmpty);
        expect(snapshots.single.properties[0xd195], u16(7));
        saved = true;
      }, (_) {});
      expect(saved, true);
      expect(fixture.slots[1]![0xd19f], u16(30));
      expect(fixture.slots[1]![0xd195], u16(7));
      final current = (await camera.backup({1})).single;
      await camera.editSlot(
        current,
        SlotEdit(current.rawName, {...current.values, 0xd19f: 10, 0xd195: 3}),
        (_) async {},
      );
      expect(fixture.slots[1]![0xd19f], u16(10));
      expect(fixture.slots[1]![0xd195], u16(7));
      fixture.slots[1]![0xd195] = u16(8);
      await camera.restore(originals.first);
      expect(fixture.slots[1]![0xd195], u16(8));
      for (final entry in originals.first.properties.entries) {
        if (entry.key != 0xd195) {
          expect(fixture.slots[1]![entry.key], entry.value);
        }
      }
      expect(fixture.slots[2].toString(), untouched);
      expect(fixture.written, isNot(contains(0xd195)));
      expect(fixture.selected, 1);
    },
  );

  test(
    'X-T5 rejects direct grain writes and grain-only edit is a no-op',
    () async {
      final fixture = Xt5ObservedFixture();
      final camera = FujiCamera(fixture);
      await camera.inspect();
      final original = await camera.readCurrentSlot();
      fixture.commands.clear();
      await expectLater(camera.set(0xd195, u16(1)), throwsStateError);
      await camera.editSlot(
        original,
        SlotEdit(original.rawName, {...original.values, 0xd195: 5}),
        (_) async => fail('No changes should be persisted'),
      );
      expect(fixture.commands, isEmpty);
    },
  );

  test('X-T5 failed durable backup prevents every recipe write', () async {
    final fixture = Xt5ObservedFixture();
    final camera = FujiCamera(fixture);
    await camera.inspect();
    await expectLater(
      BatchWriter(camera).apply({2: Recipe.fresh()}, (_) async {
        throw StateError('disk full');
      }, (_) {}),
      throwsA(
        isA<BatchApplyFailure>().having(
          (e) => e.writeAttempted,
          'writeAttempted',
          false,
        ),
      ),
    );
    expect(fixture.written, isEmpty);
    expect(fixture.selected, 1);
  });

  for (final failure in ['readback', 'refused', 'grain-side-effect']) {
    test(
      'X-T5 $failure is reported and selector restored without grain writes',
      () async {
        final fixture = Xt5ObservedFixture(
          changeGrainOnColor: failure == 'grain-side-effect',
        );
        if (failure == 'readback') fixture.corrupt = true;
        if (failure == 'refused') {
          fixture.rejecting.add(0xd19f);
          fixture.slots[2]![0xd19f] = u16(20);
        }
        final camera = FujiCamera(fixture);
        await camera.inspect();
        await expectLater(camera.write(2, Recipe.fresh()), throwsStateError);
        expect(fixture.written, isNot(contains(0xd195)));
        expect(fixture.selected, 1);
      },
    );
  }

  test(
    'X-T5 4.31 fallback does not hide another error or read-only descriptor',
    () async {
      for (final fixture in [
        Xm5Fixture(
          model: 'X-T5',
          firmware: '4.31',
          rejectDescriptor: 0xd18c,
          descriptorErrorCode: 0x200f,
        ),
        Xm5Fixture(
          model: 'X-T5',
          firmware: '4.31',
          rejectDescriptor: 0xd18c,
          readOnlyProperty: 0xd1a2,
        ),
      ]) {
        final camera = FujiCamera(fixture);
        await camera.inspect();
        await expectLater(camera.validateAccess(), throwsStateError);
        expect(fixture.selectedSlots, isEmpty);
        expect(fixture.written, isEmpty);
      }
    },
  );

  for (final readFailure in [false, true]) {
    test(
      'X-T5 diagnostic stops and restores on ${readFailure ? 'read failure' : 'ignored selector'}',
      () async {
        final fixture = Xt5ObservedFixture(
          ignoreCandidate: readFailure ? null : 2,
          failReadAt: readFailure ? 3 : null,
        );
        final camera = FujiCamera(fixture);
        await camera.inspect();
        final result = await camera.probeXt5Slots();
        expect(result['success'], false);
        expect(result['originalSelectorRestored'], true);
        expect(fixture.selected, 1);
        expect(fixture.written, isEmpty);
      },
    );
  }
  for (final firmware in ['1.00', '4.30', '4.31', '4.32', '9.99', 'unknown']) {
    test(
      'X-T5 $firmware prepares applies restores and probes with grain preserved',
      () async {
        final fixture = Xt5ObservedFixture(firmware: firmware);
        final camera = FujiCamera(fixture);
        await camera.inspect();
        await camera.validateAccess();
        expect(fixture.selectedSlots, isEmpty);
        final originals = await camera.backup({1, 7});
        await camera.validatePlan({7: Recipe.fresh()});
        await camera.write(7, Recipe.fresh());
        await camera.restore(originals.last);
        expect(
          (await camera.backup({7})).single.toJson(),
          originals.last.toJson(),
        );
        expect(
          (await camera.backup({1})).single.toJson(),
          originals.first.toJson(),
        );
        fixture.written.clear();
        final probe = await camera.probeXt5Slots();
        expect(probe['success'], true);
        expect(fixture.written, isEmpty);
        expect(fixture.selected, 1);
      },
    );
  }

  test(
    'X-T5 without descriptor operation preserves grain during write and restore',
    () async {
      final fixture = Xm5Fixture(
        model: 'X-T5',
        firmware: 'unknown',
        descriptorOperation: false,
      );
      fixture.slots[4]![0xd195] = u16(7);
      final camera = FujiCamera(fixture);
      await camera.inspect();
      await camera.validateAccess();
      final snapshot = (await camera.backup({4})).single;
      await camera.write(4, Recipe.fresh());
      await camera.restore(snapshot);
      expect(fixture.commands, isNot(contains(0x1014)));
      expect(fixture.written, isNot(contains(0xd195)));
      expect(fixture.slots[4]![0xd195], u16(7));
    },
  );
}
