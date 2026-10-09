import 'dart:convert';
import 'dart:io';

import 'camera/camera.dart';
import 'camera/ptp.dart';
import 'updates.dart';

// Uses the exact app transport and model checks. Only writeBack sends property
// writes, and it writes back the bytes it just read so no setting changes.
Future<int> diagnoseCamera(
  String outputPath, {
  bool scanSlots = false,
  bool writeBack = false,
  bool capabilities = false,
}) async {
  final transport = NativeTransport();
  final report = <String, dynamic>{
    'appVersion': appRelease,
    'recipeWrites': false,
    'writeBack': writeBack,
    'scanSlots': scanSlots,
    'capabilities': capabilities,
    'slotSelectionWrites': scanSlots || writeBack,
  };
  var code = 0;
  try {
    final devices = await transport.discover();
    report['deviceCount'] = devices.length;
    if (devices.length != 1) {
      throw StateError('Connect exactly one Fujifilm camera.');
    }
    report['transport'] = (devices.single['id'] as String).startsWith('wpd:')
        ? 'WPD'
        : 'USB';
    await transport.open(devices.single['id'] as String);
    final camera = FujiCamera(transport);
    await camera.inspect(requireRecipeProperties: !capabilities);
    report['model'] = camera.identity!.model;
    report['firmware'] = camera.identity!.firmware;
    report['slotCount'] = camera.profile.slotCount;
    if (capabilities) {
      report['capabilityReport'] = await camera.probeCapabilities();
    } else {
      report['currentSlot'] = Reader(await camera.read(0xd18c)).read16();
      report['filmSimulation'] = Reader(await camera.read(0xd192)).read16();
    }
    if (scanSlots) {
      final snapshots = await camera.backup(camera.profile.slots);
      report['slots'] = [
        for (final s in snapshots)
          {
            'slot': s.slot,
            'name': s.name,
            'film': s.film,
            'values': s.values.map((k, v) => MapEntry(k.toRadixString(16), v)),
          },
      ];
      report['restoredSlot'] = Reader(await camera.read(0xd18c)).read16();
      if (report['restoredSlot'] != report['currentSlot']) {
        throw StateError('Slot was not restored');
      }
    }
    if (writeBack) {
      report['recipeWrites'] = true;
      report['writeBack'] = await camera.probeWriteBack(camera.profile.slots);
      report['restoredSlot'] = Reader(await camera.read(0xd18c)).read16();
    }
    report['success'] = true;
  } catch (e) {
    report['success'] = false;
    report['error'] = '$e';
    code = 1;
  } finally {
    await transport.close();
  }
  await File(outputPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
  return code;
}
