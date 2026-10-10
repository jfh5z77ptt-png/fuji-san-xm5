#!/usr/bin/env python3
"""Run the real protocol/model sources offline using an existing Dart SDK.
No Flutter bootstrap, package download, device access or network calls.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--dart', required=True, help='Path to installed Dart executable')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='fuji-xm5-protocol-') as directory:
    target = Path(directory)
    (target / 'camera').mkdir()
    (target / 'domain').mkdir()
    for name in ['camera/camera.dart', 'camera/model.dart', 'domain/recipe.dart', 'diagnostic_log.dart']:
        shutil.copyfile(root / 'lib' / name, target / name)
    ptp = (root / 'lib/camera/ptp.dart').read_text()
    ptp = ptp[:ptp.index('class NativeTransport')]
    ptp = ptp.replace("import 'package:flutter/services.dart';\n", '').replace("import '../diagnostic_log.dart';\n", '')
    (target / 'camera/ptp.dart').write_text(ptp)
    fixture = (root / 'test/write_verify_test.dart').read_text()
    fixture = fixture[fixture.index('class CameraFixture'):fixture.index('void main()')]
    xm5 = (root / 'test/xm5_test.dart').read_text()
    xm5 = xm5[xm5.index('Uint8List u32'):xm5.index('void main()')]
    runner = r'''
import 'dart:typed_data';
import 'camera/camera.dart';
import 'camera/model.dart';
import 'camera/ptp.dart';
import 'domain/recipe.dart';

FIXTURES
void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
Future<void> fails(Future<void> Function() action, bool Function(Object) matches) async {
  try { await action(); } catch (error) {
    check(matches(error), 'Wrong exception: $error');
    return;
  }
  throw StateError('Expected failure');
}
Future<void> main() async {
  var passed = 0;
  Future<void> run(String name, Future<void> Function() body) async {
    await body(); passed++; print('PASS $name');
  }
  await run('model and slot counts', () async {
    check(CameraModel.xm5.slots.join(',') == '1,2,3,4', 'X-M5 banks');
    check(CameraModel.x100vi.slots.length == 7, 'X100VI banks');
    check(CameraModel.fromName('X-T5') == null, 'Unsupported model');
  });
  await run('X-M5 scan, write, restore, untouched bank and selector', () async {
    final fixture = Xm5Fixture(), camera = FujiCamera(Xm5Fixture());
    final connected = FujiCamera(fixture); await connected.inspect();
    final backup = await connected.backup(connected.profile.slots);
    check(backup.length == 4 && fixture.written.isEmpty, 'Four-bank scan');
    await connected.write(1, Recipe.fresh());
    check(Reader(fixture.slots[1]![0xd18d]!).string() == 'My Recipe', 'Write');
    check(Reader(fixture.slots[2]![0xd18d]!).string() == 'Original 2', 'Other bank');
    await connected.restore(backup.first);
    check(Reader(fixture.slots[1]![0xd18d]!).string() == 'Original 1', 'Restore');
    check(fixture.selected == 4, 'Selector');
    check(fixture.selectedSlots.every((s) => s <= 4), 'No C5-C7');
    check(camera.identity == null, 'Unconnected instance');
  });
  await run('out-of-range bank rejected before USB traffic', () async {
    final fixture = Xm5Fixture(), camera = FujiCamera(Xm5Fixture());
    final connected = FujiCamera(fixture); await connected.inspect(); fixture.commands.clear();
    await fails(() async { await connected.backup({1, 5}); }, (e) => e is RangeError);
    await fails(() => connected.write(7, Recipe.fresh()), (e) => e is RangeError);
    check(fixture.commands.isEmpty && camera.identity == null, 'No commands');
  });
  await run('no X100VI descriptor fallback on X-M5', () async {
    final fixture = Xm5Fixture()..descriptorsUnavailable = true;
    final camera = FujiCamera(fixture); await camera.inspect();
    await fails(() => camera.write(1, Recipe.fresh()), (e) => e is PtpResponseException);
    check(fixture.written.isEmpty && fixture.selected == 4, 'No recipe writes');
  });
  await run('late invalid descriptor causes zero recipe writes', () async {
    final fixture = Xm5Fixture(rejectDescriptor: 0xd18d);
    final camera = FujiCamera(fixture); await camera.inspect();
    await fails(() => camera.write(1, Recipe.fresh()), (e) => e is PtpResponseException);
    check(fixture.written.isEmpty && fixture.selected == 4, 'Preflight all fields');
  });
  await run('incomplete camera diagnosed read-only without serial or recipe names', () async {
    final fixture = Xm5Fixture(missingProperty: 0xd193);
    final camera = FujiCamera(fixture);
    await fails(() => camera.inspect(), (e) => e is StateError);
    check(camera.identity == null, 'Failed inspect reset');
    await camera.inspect(requireRecipeProperties: false);
    final report = await camera.probeCapabilities();
    check(!(report['properties'] as Map).containsKey('d193'), 'Missing property');
    check(!report.toString().contains('test-private-serial'), 'Serial omitted');
    check(!report.toString().contains('Original 4'), 'Recipe name omitted');
    check(!fixture.commands.contains(0x1016) && fixture.selected == 4, 'No setter');
  });
  await run('raw write-back disabled for X-M5', () async {
    final fixture = Xm5Fixture(); final camera = FujiCamera(fixture);
    await camera.inspect(); fixture.commands.clear();
    await fails(() async { await camera.probeWriteBack({1}); }, (e) => e is StateError);
    check(fixture.commands.isEmpty, 'No commands');
  });
  await run('unsupported model rejected', () async {
    final camera = FujiCamera(Xm5Fixture(model: 'X-T5'));
    await fails(() => camera.inspect(), (e) => e is StateError);
    check(camera.identity == null, 'Unsupported identity');
  });
  await run('X100VI 1.32 fallback and seven-bank scan preserved', () async {
    final fixture = CameraFixture()..descriptorsUnavailable = true;
    final camera = FujiCamera(fixture)..identity = CameraIdentity('X100VI', '1.32', 'test', {
      0xd18d, ...settings.map((s) => s.id),
    });
    final backup = await camera.backup(camera.profile.slots);
    check(backup.length == 7, 'Seven banks');
    await camera.write(7, Recipe.fresh()); await camera.restore(backup.last);
    check(fixture.selected == 4, 'Selector restored');
    check(Reader(fixture.slots[7]![0xd18d]!).string() == 'Original 7', 'C7 restored');
  });
  await run('X-M5 1.20 candidate selection, restoration and zero recipe writes', () async {
    final fixture = Xm5ProbeFixture(); final camera = FujiCamera(fixture);
    await camera.inspect(); final report = await camera.probeXm5Slots();
    check(report['success'] == true, 'Probe success');
    check(report['originalSelectorRestored'] == true && report['originalRecipeFieldsUnchanged'] == true, 'Restored content');
    check(report['distinctRecipeSignatures'] == 4, 'Distinct bank names, kept private');
    check(fixture.selectorWriteAttempts.join(',') == '1,2,3,4,2', 'Bounded selection');
    check(fixture.written.isEmpty && !fixture.commands.contains(0x1014), 'Only selector writes, no descriptor assumption');
    check(!report.toString().contains('Original') && !report.toString().contains('test-private-serial'), 'No names or serial');
    check(report['physicalCMappingVerified'] == false, 'No physical bank mapping claim');
  });
  await run('ignored selector stops probe and restores original', () async {
    final fixture = Xm5ProbeFixture(ignoreCandidate: 1); final camera = FujiCamera(fixture);
    await camera.inspect(); final report = await camera.probeXm5Slots();
    check(report['success'] == false && report['originalSelectorRestored'] == true, 'Mismatch reported and restored');
    check(fixture.selectorWriteAttempts.join(',') == '1,2' && fixture.written.isEmpty, 'Stop at mismatch');
  });
  await run('read failure preserves partial probe and restoration', () async {
    final fixture = Xm5ProbeFixture(failReadAt: 3); final camera = FujiCamera(fixture);
    await camera.inspect(); final report = await camera.probeXm5Slots();
    check(report['success'] == false && report['originalRecipeFieldsUnchanged'] == true, 'Failed read and unchanged original');
    check(fixture.selectorWriteAttempts.join(',') == '1,2,3,2' && fixture.written.isEmpty, 'Restores after failure');
  });
  await run('restoration failure is explicit in diagnostic report', () async {
    final fixture = Xm5ProbeFixture(failRestoration: true); final camera = FujiCamera(fixture);
    await camera.inspect(); final report = await camera.probeXm5Slots();
    check(report['success'] == false && report['originalSelectorRestored'] == false && report.containsKey('restoreError'), 'Never claim restored');
    check(fixture.written.isEmpty, 'No recipe writes');
  });
  await run('unobserved firmware and malformed selector prevent probe writes', () async {
    final fixture = Xm5Fixture(firmware: '1.21'); final camera = FujiCamera(fixture);
    await camera.inspect(); fixture.commands.clear();
    await fails(() async { await camera.probeXm5Slots(); }, (e) => e is StateError);
    check(fixture.commands.isEmpty, 'Unknown firmware, no USB traffic');
    final malformed = Xm5ProbeFixture(malformedSelector: true); final other = FujiCamera(malformed);
    await other.inspect();
    await fails(() async { await other.probeXm5Slots(); }, (e) => e is StateError);
    check(malformed.selectorWriteAttempts.isEmpty, 'Malformed selector, no writes');
  });
  await run('X-M5 1.20 observed schema supports bounded scan, write and restore', () async {
    final fixture = Xm5ObservedFixture(); final camera = FujiCamera(fixture);
    await camera.inspect(); final backup = await camera.backup(camera.profile.slots);
    check(backup.length == 4 && backup.first.values[0xd192] == 11 && backup.first.values[0xd190] == 400, 'Observed C1');
    check(backup.first.values[0xd19d] == -10 && backup.first.values[0xd1a1] == 20480, 'Signed and enum encodings');
    check(fixture.written.isEmpty, 'Read-only recipe scan');
    await camera.write(4, Recipe.fresh()); await camera.restore(backup.last);
    final restored = (await camera.backup({4})).single;
    check(restored.rawName == backup.last.rawName && restored.values.toString() == backup.last.values.toString(), 'Recipe restored');
    check(fixture.selected == 2 && !fixture.written.contains(0xd1a5), 'Selector and unknown fields preserved');
  });
  await run('X-M5 one-field edit persists backup before the only recipe write', () async {
    final fixture = Xm5ObservedFixture(); final camera = FujiCamera(fixture);
    await camera.inspect(); final original = (await camera.backup({4})).single;
    var backedUp = false;
    await camera.editSlot(original, SlotEdit(original.rawName, {...original.values, 0xd19f: 10}), (snapshots) async {
      check(fixture.written.isEmpty && snapshots.single.rawName == original.rawName, 'Backup before setter');
      backedUp = true;
    });
    check(backedUp && fixture.written.join(',') == '${0xd19f}' && fixture.selected == 2, 'Only color changed');
  });
  await run('X-M5 fallback is exact to firmware and GeneralError response', () async {
    final fixture = Xm5Fixture(firmware: '1.20', rejectDescriptor: 0xd18c, descriptorErrorCode: 0x200f);
    final camera = FujiCamera(fixture); await camera.inspect();
    await fails(() async { await camera.backup({1}); }, (e) => e is PtpResponseException);
    check(fixture.selectedSlots.isEmpty, 'Different error blocked');
    final unknown = Xm5Fixture(firmware: '1.21')..descriptorsUnavailable = true;
    final other = FujiCamera(unknown); await other.inspect();
    await fails(() => other.write(1, Recipe.fresh()), (e) => e is PtpResponseException);
    check(unknown.selectedSlots.isEmpty && unknown.written.isEmpty, 'Unknown firmware blocked');
  });
  await run('invalid X-M5 restore value and bank fail before USB traffic', () async {
    final fixture = Xm5ObservedFixture(); final camera = FujiCamera(fixture);
    await camera.inspect(); final snapshot = (await camera.backup({4})).single;
    fixture.commands.clear();
    await fails(() => camera.restore(Snapshot(4, {...snapshot.properties, 0xd1a2: u16(500)})), (e) => e is StateError);
    await fails(() => camera.write(5, Recipe.fresh()), (e) => e is RangeError);
    check(fixture.commands.isEmpty && fixture.written.isEmpty, 'No partial mutation');
  });
  print('$passed offline protocol checks passed (simulated transport, no hardware).');
}
'''
    runner = runner.replace('FIXTURES', fixture + '\n' + xm5)
    (target / 'check.dart').write_text(runner)
    subprocess.run([args.dart, str(target / 'check.dart')], check=True, cwd=target)
