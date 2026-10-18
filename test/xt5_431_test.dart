import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuji_san/camera/camera.dart';
import 'package:fuji_san/camera/ptp.dart';

import 'xm5_test.dart' show Xm5Fixture;

class Xt5ObservedFixture extends Xm5Fixture {
  Xt5ObservedFixture({
    this.ignoreCandidate,
    this.failReadAt,
    String firmware = '4.31',
  }) : super(model: 'X-T5', firmware: firmware) {
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
    for (final bank in slots.values) {
      for (final e in observed.entries) {
        bank[e.key] = u16(e.value);
      }
    }
  }
  final int? ignoreCandidate, failReadAt;
  @override
  Future<Uint8List> command(
    int code, {
    List<int> params = const [],
    Uint8List? outgoing,
  }) {
    if (code == 0x1016 &&
        params.first == 0xd18c &&
        Reader(outgoing!).read16() == ignoreCandidate) {
      return Future.value(Uint8List(0));
    }
    if (code == 0x1015 && params.first == 0xd192 && selected == failReadAt) {
      throw PtpResponseException(0x2002, code);
    }
    return super.command(code, params: params, outgoing: outgoing);
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
  test(
    'X-T5 diagnostic rejects other firmware before any selector writes',
    () async {
      final fixture = Xt5ObservedFixture(firmware: '4.32');
      final camera = FujiCamera(fixture);
      await camera.inspect();
      fixture.commands.clear();
      await expectLater(camera.probeXt5Slots(), throwsStateError);
      expect(fixture.commands, isEmpty);
      expect(fixture.written, isEmpty);
    },
  );
}
