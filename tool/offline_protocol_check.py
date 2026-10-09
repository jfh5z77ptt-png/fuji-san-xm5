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
  print('$passed offline protocol checks passed (simulated transport, no hardware).');
}
'''
    runner = runner.replace('FIXTURES', fixture + '\n' + xm5)
    (target / 'check.dart').write_text(runner)
    subprocess.run([args.dart, str(target / 'check.dart')], check=True, cwd=target)
