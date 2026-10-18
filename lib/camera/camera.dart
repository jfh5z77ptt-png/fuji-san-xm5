import 'dart:typed_data';

import '../domain/recipe.dart';
import 'ptp.dart';
import '../diagnostic_log.dart';
import 'model.dart';

class CameraIdentity {
  CameraIdentity(this.model, this.firmware, this.serial, this.properties);
  final String model, firmware, serial;
  final Set<int> properties;
  CameraModel get profile =>
      CameraModel.fromName(model) ??
      (throw StateError('지원하지 않는 카메라 모델: $model'));
}

class Snapshot {
  Snapshot(this.slot, this.properties, {this.normalizeGrainOff = true});
  final int slot;
  final bool normalizeGrainOff;
  final Map<int, Uint8List> properties;
  String get rawName => Reader(properties[0xd18d]!).string();
  String get name {
    final name = Reader(properties[0xd18d]!).string().trim();
    return name.isEmpty ? '이름 없는 레시피' : name;
  }

  Map<int, int> get values => {
    for (final s in settings)
      s.id:
          normalizeGrainOff &&
              s.id == 0xd195 &&
              Reader(properties[s.id]!).read16() == 6
          ? 1
          : s.signed
          ? ByteData.sublistView(properties[s.id]!).getInt16(0, Endian.little)
          : Reader(properties[s.id]!).read16(),
  };

  String get film => filmNames[values[0xd192]] ?? '알 수 없는 필름';
  Map<String, dynamic> toJson() => {
    'slot': slot,
    'properties': properties.map(
      (k, v) => MapEntry(k.toRadixString(16), v.toList()),
    ),
  };
  factory Snapshot.fromJson(Map<String, dynamic> j) {
    final slot = j['slot'] as int;
    if (slot < 1 || slot > 7) {
      throw const FormatException('Invalid backup slot');
    }
    final p = (j['properties'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(
        int.parse(k, radix: 16),
        Uint8List.fromList((v as List).cast<int>()),
      ),
    );
    if (!p.containsKey(0xd18d) || settings.any((s) => p[s.id]?.length != 2)) {
      throw const FormatException('Incomplete backup');
    }
    return Snapshot(slot, p);
  }
}

abstract interface class RecipeCamera {
  Future<List<Snapshot>> backup(Set<int> slots);
  Future<void> write(int slot, Recipe recipe);
  Future<void> restore(Snapshot snapshot);
}

class FujiCamera implements RecipeCamera {
  FujiCamera(this.transport);
  final CameraTransport transport;
  CameraIdentity? identity;
  CameraModel get profile => identity?.profile ?? CameraModel.x100vi;
  Set<int> operations = {};
  bool _knownSchemaOnly = false;
  bool get xm5Firmware120 =>
      identity?.model == 'X-M5' && identity?.firmware == '1.20';
  bool get xt5Firmware431 =>
      identity?.model == 'X-T5' && identity?.firmware == '4.31';
  Future<Uint8List> read(int prop) => transport.command(0x1015, params: [prop]);
  Future<void> set(int prop, Uint8List value) async {
    await transport.command(0x1016, params: [prop], outgoing: value);
  }

  Future<void> inspect({bool requireRecipeProperties = true}) async {
    identity = null;
    operations = {};
    _knownSchemaOnly = false;
    final r = Reader(await transport.command(0x1001));
    r.read16();
    r.read32();
    r.read16();
    r.string();
    r.read16();
    final ops = r.array16();
    r.array16();
    final props = r.array16().toSet();
    r.array16();
    r.array16();
    final manufacturer = r.string(),
        model = r.string(),
        firmware = r.string(),
        serial = r.string();
    DiagnosticLog.instance.protect(serial);
    DiagnosticLog.instance.camera.addAll({
      'model': DiagnosticLog.instance.redact(model, max: 25),
      'firmware': DiagnosticLog.instance.redact(firmware, max: 25),
    });
    DiagnosticLog.instance.add(
      'camera',
      'deviceInfo ops=${ops.map((p) => p.toRadixString(16)).join(',')} properties=${props.map((p) => p.toRadixString(16)).join(',')}',
    );
    if (!manufacturer.toUpperCase().contains('FUJI') ||
        CameraModel.fromName(model) == null) {
      throw StateError(
        '지원 모델은 X100VI / X-M5(실험적) / X-T5(실험적)입니다. 감지: $manufacturer $model',
      );
    }
    operations = ops.toSet();
    if (requireRecipeProperties &&
        (!ops.contains(0x1014) ||
            !ops.contains(0x1015) ||
            !ops.contains(0x1016) ||
            !props.contains(0xd18c) ||
            !props.contains(0xd18d) ||
            settings.any((s) => !props.contains(s.id)))) {
      throw StateError(
        '카메라가 필요한 레시피 속성을 제공하지 않습니다. USB RAW CONV./BACKUP RESTORE 모드를 확인하세요.',
      );
    }
    identity = CameraIdentity(
      model.trim().toUpperCase(),
      firmware,
      serial,
      props,
    );
  }

  void _ready() {
    if (identity == null) throw StateError('카메라 모델을 먼저 확인하세요.');
  }

  // Reads the current bank without selecting a bank, asking for a descriptor,
  // or interpreting unknown wire enums (e.g. X-T5 4.31 grain value 7).
  Future<Snapshot> readCurrentSlot() async {
    _ready();
    final original = await read(0xd18c);
    if (original.length != 2) {
      throw const FormatException('슬롯 선택값 길이가 올바르지 않습니다.');
    }
    final slot = Reader(original).read16();
    profile.validateSlots([slot]);
    final fields = <int, Uint8List>{0xd18d: await read(0xd18d)};
    DiagnosticLog.instance.protect(Reader(fields[0xd18d]!).string());
    for (final setting in settings) {
      final value = await read(setting.id);
      if (value.length != 2) {
        throw FormatException('${setting.label} 조회값 길이 오류');
      }
      fields[setting.id] = value;
    }
    if (!_same(original, await read(0xd18c))) {
      throw StateError('조회 중 카메라 슬롯이 바뀌었습니다. 다시 조회하세요.');
    }
    return Snapshot(slot, fields, normalizeGrainOff: false);
  }

  // Read and validate access before selecting any bank or changing recipes.
  Future<void> validateAccess() async {
    _ready();
    final selector = await read(0xd18c);
    if (selector.length != 2) {
      throw const FormatException('카메라 슬롯 선택값 길이가 올바르지 않습니다.');
    }
    profile.validateSlots([Reader(selector).read16()]);
    await _validateDescriptor(0xd18c, selector);
    final name = await read(0xd18d);
    await _validateDescriptor(0xd18d, name);
    for (final s in settings) {
      final bytes = await read(s.id);
      if (bytes.length != 2) {
        throw FormatException('${s.label} 조회값 길이가 올바르지 않습니다.');
      }
      // Grain Off has separate read and write representations.
      final value = s.id == 0xd195 && Reader(bytes).read16() == 6
          ? u16(1)
          : bytes;
      await _validateDescriptor(s.id, value);
    }
    DiagnosticLog.instance.add(
      'camera',
      _knownSchemaOnly
          ? 'access validated with bounded model schema'
          : 'access validated with camera descriptors',
    );
  }

  // Reject an incompatible plan before any bank selection or recipe write.
  Future<void> validatePlan(Map<int, Recipe> plan) async {
    _ready();
    profile.validateSlots(plan.keys);
    for (final entry in plan.entries) {
      await _validateDescriptor(0xd18c, u16(entry.key));
      for (final value in entry.value.writeValues.entries) {
        await _validateDescriptor(value.key, u16(value.value));
      }
      await _validateDescriptor(0xd18d, ptpString(entry.value.cameraName));
    }
  }

  // No SetDevicePropValue or bank selection: suitable for an unknown firmware.
  Future<Map<String, dynamic>> probeCapabilities() async {
    _ready();
    final properties = <String, dynamic>{};
    for (final id in [0xd18c, 0xd18d, ...settings.map((s) => s.id)]) {
      if (!identity!.properties.contains(id)) continue;
      final result = <String, dynamic>{};
      if (id != 0xd18d && operations.contains(0x1015)) {
        try {
          final value = await read(id);
          result['valueHex'] = _hex(value);
        } catch (e) {
          result['readError'] = '$e';
        }
      }
      if (operations.contains(0x1014)) {
        try {
          final descriptor = await transport.command(0x1014, params: [id]);
          result['descriptorHex'] = _hex(descriptor);
        } catch (e) {
          result['descriptorError'] = '$e';
        }
      }
      properties[id.toRadixString(16)] = result;
    }
    return {
      'model': identity!.model,
      'firmware': identity!.firmware,
      'slotCount': profile.slotCount,
      'experimental': profile.experimental,
      'recipeWrites': false,
      'slotSelectionWrites': false,
      'operations': operations.map((id) => id.toRadixString(16)).toList()
        ..sort(),
      'advertisedProperties':
          identity!.properties.map((id) => id.toRadixString(16)).toList()
            ..sort(),
      'properties': properties,
    };
  }

  Future<void> select(int slot) async {
    _ready();
    profile.validateSlots([slot]);
    // X-M5 1.20 selector 1..4 and restoration have been observed on hardware.
    // Other firmware must still supply a writable selector descriptor.
    if (profile.experimental) await _validateDescriptor(0xd18c, u16(slot));
    await set(0xd18c, u16(slot));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (Reader(await read(0xd18c)).read16() != slot) {
      throw StateError('슬롯 선택 검증 실패');
    }
  }

  // Explicit diagnostic for the observed X-M5 1.20 descriptor failure. This
  // bypass applies only to candidate selector values, never recipe writes.
  Future<Map<String, dynamic>> probeXm5Slots() async {
    _ready();
    if (identity!.model != 'X-M5' || identity!.firmware != '1.20') {
      throw StateError('슬롯 전환 진단은 X-M5 펌웨어 1.20 전용입니다.');
    }
    return _probeSlotSelection('xm5-slot-selection');
  }

  Future<Map<String, dynamic>> probeXt5Slots() async {
    _ready();
    if (!xt5Firmware431) {
      throw StateError('슬롯 전환 진단은 X-T5 펌웨어 4.31 전용입니다.');
    }
    return _probeSlotSelection('xt5-slot-selection');
  }

  // Explicit user-invoked diagnostic: only the selector can be written.
  // This never enables descriptor fallback or recipe writes for X-T5.
  Future<Map<String, dynamic>> _probeSlotSelection(String diagnostic) async {
    final ids = [0xd18d, ...settings.map((s) => s.id)];
    if (!operations.contains(0x1015) ||
        !operations.contains(0x1016) ||
        !identity!.properties.contains(0xd18c) ||
        ids.any((id) => !identity!.properties.contains(id))) {
      throw StateError('슬롯 진단에 필요한 USB 명령이나 속성이 없습니다.');
    }
    final original = await read(0xd18c);
    if (original.length != 2) {
      throw StateError('슬롯 선택값이 2바이트가 아니므로 진단을 중단합니다.');
    }
    final originalSlot = Reader(original).read16();
    profile.validateSlots([originalSlot]);

    Future<Map<int, Uint8List>> readFields() async {
      final fields = <int, Uint8List>{};
      for (final id in ids) {
        final value = await read(id);
        if (id == 0xd18d) {
          DiagnosticLog.instance.protect(Reader(value).string());
        } else if (value.length != 2) {
          throw StateError('속성 0x${id.toRadixString(16)} 길이 오류');
        }
        fields[id] = value;
      }
      return fields;
    }

    final before = await readFields();
    final rows = <Map<String, dynamic>>[];
    final signatures = <String>{};
    final result = <String, dynamic>{
      'diagnostic': diagnostic,
      'model': identity!.model,
      'firmware': identity!.firmware,
      'recipeWrites': false,
      'slotSelectionWrites': false,
      'physicalCMappingVerified': false,
      'originalSelector': originalSlot,
      'originalSelectorHex': _hex(original),
      'candidateSelectors': rows,
      'originalSelectorRestored': false,
      'originalRecipeFieldsUnchanged': false,
      'success': false,
    };
    var attemptedSelection = false;
    try {
      for (final candidate in profile.slots) {
        final row = <String, dynamic>{'selectorSent': candidate};
        rows.add(row);
        attemptedSelection = true;
        result['slotSelectionWrites'] = true;
        await set(0xd18c, u16(candidate));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final selected = await read(0xd18c);
        row['selectorReadHex'] = _hex(selected);
        if (!_same(selected, u16(candidate))) {
          throw StateError('선택값 $candidate 읽기 검증 실패');
        }
        row['selectorReadMatched'] = true;
        final fields = await readFields();
        row['recipeValuesHex'] = {
          for (final s in settings) s.id.toRadixString(16): _hex(fields[s.id]!),
        };
        // Names distinguish banks without exporting private recipe names.
        signatures.add(ids.map((id) => _hex(fields[id]!)).join('|'));
      }
    } catch (e) {
      result['error'] = DiagnosticLog.instance.redact('$e');
    } finally {
      if (attemptedSelection) {
        try {
          await set(0xd18c, original);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final restored = await read(0xd18c);
          result['restoredSelectorHex'] = _hex(restored);
          result['originalSelectorRestored'] = _same(restored, original);
          if (result['originalSelectorRestored'] != true) {
            throw StateError('원래 선택값을 복원하지 못했습니다.');
          }
          final after = await readFields();
          result['originalRecipeFieldsUnchanged'] = ids.every(
            (id) => _same(before[id]!, after[id]!),
          );
        } catch (e) {
          result['restoreError'] = DiagnosticLog.instance.redact('$e');
        }
      }
    }
    result['distinctRecipeSignatures'] = signatures.length;
    result['success'] =
        !result.containsKey('error') &&
        !result.containsKey('restoreError') &&
        rows.length == profile.slotCount &&
        result['originalSelectorRestored'] == true &&
        result['originalRecipeFieldsUnchanged'] == true;
    return result;
  }

  @override
  Future<List<Snapshot>> backup(Set<int> slots) async {
    _ready();
    profile.validateSlots(slots);
    if (profile.experimental) {
      for (final slot in slots) {
        await _validateDescriptor(0xd18c, u16(slot));
      }
    }
    final original = await read(0xd18c);
    final result = <Snapshot>[];
    if (xm5Firmware120) _validateKnownValue(0xd18c, original);
    Object? readFailure;
    try {
      for (final slot in slots.toList()..sort()) {
        await select(slot);
        final p = <int, Uint8List>{0xd18d: await read(0xd18d)};
        if (xm5Firmware120) _validateKnownValue(0xd18d, p[0xd18d]!);
        for (final s in settings) {
          p[s.id] = await read(s.id);
          if (p[s.id]!.length != 2) throw StateError('백업 속성 길이 오류');
          if (xm5Firmware120) {
            _validateKnownValue(
              s.id,
              s.id == 0xd195 && Reader(p[s.id]!).read16() == 6
                  ? u16(1)
                  : p[s.id]!,
            );
          }
        }
        result.add(Snapshot(slot, p));
      }
    } catch (error) {
      readFailure = error;
      rethrow;
    } finally {
      try {
        await set(0xd18c, original);
        if (!_same(await read(0xd18c), original)) {
          throw StateError('원래 C 슬롯을 복원하지 못했습니다. 카메라에서 확인하세요.');
        }
      } catch (error) {
        DiagnosticLog.instance.add('restore-error', '원래 C 슬롯 선택 복원 실패: $error');
        // Preserve the first failure for diagnosis; never replace a transport
        // failure with the secondary error from restoring the selector.
        if (readFailure == null) rethrow;
      }
    }
    return result;
  }

  bool _same(Uint8List a, Uint8List b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);

  Future<void> _validateDescriptor(int id, Uint8List bytes) async {
    if (_knownSchemaOnly) {
      _validateKnownValue(id, bytes);
      return;
    }
    late Uint8List descriptor;
    try {
      descriptor = await transport.command(0x1014, params: [id]);
    } on PtpResponseException catch (e) {
      // These exact firmware versions advertise 1014 but refuse descriptors.
      // X-M5 1.20 selector writes and reads are observed; recipe writes remain
      // experimental and use bounded schema checks plus backup/read-back.
      if (((identity?.model == 'X100VI' && identity?.firmware == '1.32') ||
              xm5Firmware120) &&
          e.operation == 0x1014 &&
          e.code == 0x2002) {
        _validateKnownValue(id, bytes);
        _knownSchemaOnly = true;
        return;
      }
      throw PtpResponseException(e.code, e.operation, property: id);
    }
    final r = Reader(descriptor);
    if (r.read16() != id) {
      throw const FormatException('Property descriptor mismatch');
    }
    final type = r.read16(), writable = r.read8();
    if (writable != 1) {
      throw StateError('속성 0x${id.toRadixString(16)}은 현재 수정할 수 없습니다.');
    }
    if (type == 0xffff && id == 0xd18d) return;
    if (type != 3 && type != 4) throw StateError('지원하지 않는 속성 자료형: $type');
    int number() {
      final n = r.read16();
      return type == 3 && n >= 32768 ? n - 65536 : n;
    }

    number();
    number();
    final form = r.read8();
    final b = ByteData.sublistView(bytes);
    final value = type == 3
        ? b.getInt16(0, Endian.little)
        : b.getUint16(0, Endian.little);
    if (form == 1) {
      final min = number(), max = number(), step = number();
      if (value < min ||
          value > max ||
          (step > 0 && (value - min) % step != 0)) {
        throw StateError('카메라 범위를 벗어난 설정: 0x${id.toRadixString(16)}');
      }
    } else if (form == 2) {
      final count = r.read16();
      final allowed = List.generate(count, (_) => number());
      if (!allowed.contains(value)) {
        throw StateError('카메라가 허용하지 않는 설정: 0x${id.toRadixString(16)}=$value');
      }
    } else if (form != 0) {
      throw const FormatException('Unknown property descriptor form');
    }
  }

  void _validateKnownValue(int id, Uint8List bytes) {
    if (!identity!.properties.contains(id)) {
      throw StateError('카메라가 지원하지 않는 속성입니다.');
    }
    if (id == 0xd18c) {
      if (bytes.length != 2) {
        throw const FormatException('Invalid selector size');
      }
      profile.validateSlots([Reader(bytes).read16()]);
      return;
    }
    if (id == 0xd18d) {
      if (bytes.length == 1 && bytes[0] == 0) return;
      final name = Reader(bytes).string();
      if (name.length > 25 || bytes.length != 1 + (name.length + 1) * 2) {
        throw const FormatException('Invalid camera name backup');
      }
      return;
    }
    final matching = settings.where((s) => s.id == id);
    if (matching.isEmpty) {
      throw StateError('지원하지 않는 레시피 속성입니다.');
    }
    final setting = matching.single;
    if (bytes.length != 2) {
      throw const FormatException('Invalid recipe property size');
    }
    final raw = ByteData.sublistView(bytes);
    final value = setting.signed
        ? raw.getInt16(0, Endian.little)
        : raw.getUint16(0, Endian.little);
    if (!setting.accepts(value)) {
      throw StateError('${profile.name} 설정 범위를 벗어났습니다: ${setting.label}');
    }
  }

  Future<void> _write(int slot, Map<int, Uint8List> p) async {
    _ready();
    profile.validateSlots([slot]);
    if (xm5Firmware120) {
      for (final e in p.entries) {
        _validateKnownValue(e.key, e.value);
      }
    }
    if (profile.experimental) await _validateDescriptor(0xd18c, u16(slot));
    final original = await read(0xd18c);
    if (xm5Firmware120) _validateKnownValue(0xd18c, original);
    Object? writeFailure;
    try {
      await select(slot);
      // Check every value before the first recipe write. A late unsupported
      // setting must not leave earlier fields partially changed.
      for (final e in p.entries) {
        await _validateDescriptor(e.key, e.value);
      }
      for (final e in p.entries) {
        try {
          await set(e.key, e.value);
        } on PtpResponseException catch (error) {
          // A real X100VI 1.32 refused a restore of values the slot already
          // held. A refused write is tolerated only when nothing has to change;
          // the read-back pass below still checks every property.
          if (error.code != 0x201c ||
              !_holds(e.key, e.value, await read(e.key))) {
            throw StateError(
              'C$slot ${_label(e.key)} 값을 카메라가 거부했습니다 '
              '(응답 0x${error.code.toRadixString(16)}, 보낸 값 ${_hex(e.value)}). '
              '이 항목 이전에 보낸 설정은 적용되었을 수 있습니다.',
            );
          }
        }
      }
      for (final e in p.entries) {
        final got = await read(e.key);
        if (!_holds(e.key, e.value, got)) {
          throw StateError(
            'C$slot 속성 0x${e.key.toRadixString(16)} 읽기 검증 실패. 백업에서 복원하세요.',
          );
        }
      }
    } catch (error) {
      writeFailure = error;
      rethrow;
    } finally {
      try {
        await set(0xd18c, original);
        if (!_equal(await read(0xd18c), original)) {
          throw StateError('원래 C 슬롯 복원 실패. 카메라에서 확인하세요.');
        }
      } catch (error) {
        DiagnosticLog.instance.add('restore-error', '원래 C 슬롯 선택 복원 실패: $error');
        if (writeFailure == null) rethrow;
      }
    }
  }

  // Grain "Off" is written as 1 and read back as 6.
  bool _holds(int id, Uint8List wanted, Uint8List got) =>
      _equal(got, wanted) ||
      (id == 0xd195 &&
          Reader(wanted).read16() == 1 &&
          got.length == 2 &&
          Reader(got).read16() == 6);

  String _label(int id) =>
      '${id == 0xd18d ? '이름' : settings.firstWhere((s) => s.id == id).label} '
      '(0x${id.toRadixString(16)})';

  String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  // Diagnostic: writes each known property of each slot back with the bytes just
  // read, so no setting changes, and records the camera's response to each write.
  Future<List<Map<String, dynamic>>> probeWriteBack(Set<int> slots) async {
    _ready();
    profile.validateSlots(slots);
    if (profile.experimental) {
      throw StateError(
        '${profile.name} 실험적 모드는 원시 쓰기 진단을 지원하지 않습니다. --diagnose-capabilities를 사용하세요.',
      );
    }
    final original = await read(0xd18c);
    final result = <Map<String, dynamic>>[];
    try {
      for (final slot in slots.toList()..sort()) {
        await select(slot);
        final writes = <String, dynamic>{};
        for (final id in [...settings.map((s) => s.id), 0xd18d]) {
          final value = await read(id);
          var response = 0x2001;
          try {
            await set(id, value);
          } on PtpResponseException catch (error) {
            response = error.code;
          }
          writes[id.toRadixString(16)] = {
            'value': _hex(value),
            'response': '0x${response.toRadixString(16)}',
            'unchanged': _equal(await read(id), value),
          };
        }
        result.add({'slot': slot, 'writes': writes});
      }
    } finally {
      await set(0xd18c, original);
      if (!_equal(await read(0xd18c), original)) {
        throw StateError('원래 C 슬롯 복원 실패. 카메라에서 확인하세요.');
      }
    }
    return result;
  }

  Future<void> editSlot(
    Snapshot original,
    SlotEdit edit,
    Future<void> Function(List<Snapshot>) persist,
  ) async {
    final changes = edit.changes(original);
    if (changes.isEmpty) return;
    final current = (await backup({original.slot})).single;
    if (original.properties.entries.any(
      (e) =>
          current.properties[e.key] == null ||
          !_equal(e.value, current.properties[e.key]!),
    )) {
      throw StateError('편집 중 카메라 설정이 바뀌었습니다. 닫고 새로고침한 뒤 다시 편집하세요.');
    }
    await persist([current]);
    await _write(original.slot, changes);
  }

  @override
  Future<void> write(int slot, Recipe recipe) => _write(slot, {
    for (final e in recipe.writeValues.entries) e.key: u16(e.value),
    0xd18d: ptpString(recipe.cameraName),
  });
  @override
  Future<void> restore(Snapshot snapshot) async {
    final values = <int, int>{};
    for (final s in settings) {
      final b = ByteData.sublistView(snapshot.properties[s.id]!);
      values[s.id] = s.signed
          ? b.getInt16(0, Endian.little)
          : b.getUint16(0, Endian.little);
    }
    final p = <int, Uint8List>{};
    for (final s in settings) {
      if (applicable(s.id, values)) {
        p[s.id] = s.id == 0xd195 && values[s.id] == 6
            ? u16(1)
            : snapshot.properties[s.id]!;
      }
    }
    p[0xd18d] = snapshot.properties[0xd18d]!;
    await _write(snapshot.slot, p);
  }
}

class SlotEdit {
  SlotEdit(this.name, Map<int, int> values) : values = Map.unmodifiable(values);
  final String name;
  final Map<int, int> values;

  Map<int, Uint8List> changes(Snapshot original) {
    if (values.length != settings.length ||
        settings.any((s) => !values.containsKey(s.id))) {
      throw const FormatException('불완전한 레시피 설정입니다.');
    }
    final before = original.values;
    final result = <int, Uint8List>{};
    for (final setting in settings) {
      if (!applicable(setting.id, values) ||
          values[setting.id] == before[setting.id]) {
        continue;
      }
      if (!setting.accepts(values[setting.id]!)) {
        throw FormatException('${setting.label} 설정값을 확인하세요.');
      }
      result[setting.id] = u16(values[setting.id]!);
    }
    if (name != original.rawName) {
      if (!RegExp(r'^[A-Za-z0-9 _.,+()\-]{0,25}$').hasMatch(name)) {
        throw const FormatException('카메라 이름은 영문·숫자·공백·_.,+()- 25자 이내로 입력하세요.');
      }
      result[0xd18d] = ptpString(name);
    }
    return result;
  }
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class BatchWriter {
  BatchWriter(this.camera);
  final RecipeCamera camera;
  bool _running = false;
  Future<void> apply(
    Map<int, Recipe> plan,
    Future<void> Function(List<Snapshot>) persist,
    void Function(String) report,
  ) async {
    if (_running) throw StateError('이미 전송 중입니다.');
    if (plan.isEmpty || plan.keys.any((s) => s < 1 || s > 7)) {
      throw ArgumentError('슬롯 C1~C7을 선택하세요.');
    }
    _running = true;
    var stage = '원본 슬롯 조회';
    var backupSaved = false;
    var writeAttempted = false;
    try {
      report('원본 슬롯 백업 중');
      final backup = await camera.backup(plan.keys.toSet());
      if (backup.length != plan.length ||
          backup.map((s) => s.slot).toSet().length != plan.length ||
          backup
              .map((s) => s.slot)
              .toSet()
              .difference(plan.keys.toSet())
              .isNotEmpty) {
        throw StateError('백업이 완전하지 않습니다.');
      }
      stage = '백업 파일 저장';
      report('원본 백업 파일 저장 중');
      await persist(
        backup,
      ); // A durable backup is required before any recipe write.
      backupSaved = true;
      for (final slot in plan.keys.toList()..sort()) {
        stage = 'C$slot 쓰기 및 검증';
        report('C$slot 쓰기 및 검증 중');
        writeAttempted = true;
        await camera.write(slot, plan[slot]!);
        report('C$slot 검증 완료');
      }
    } catch (error, stack) {
      Error.throwWithStackTrace(
        BatchApplyFailure(error, stage, backupSaved, writeAttempted),
        stack,
      );
    } finally {
      _running = false;
    }
  }
}

class BatchApplyFailure extends StateError {
  BatchApplyFailure(
    this.cause,
    this.stage,
    this.backupSaved,
    this.writeAttempted,
  ) : super(
        writeAttempted
            ? '$stage 단계에서 중단했습니다. 일부 설정이 적용되었을 수 있습니다. 원본 백업은 저장되어 있습니다. 연결을 다시 확인한 뒤 백업 메뉴에서 복원할 수 있습니다. $cause'
            : '$stage 단계에서 중단했습니다. 레시피 설정 쓰기는 시작하지 않았습니다. $cause',
      );
  final Object cause;
  final String stage;
  final bool backupSaved, writeAttempted;
}
