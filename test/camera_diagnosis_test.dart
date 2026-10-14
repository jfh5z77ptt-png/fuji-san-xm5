import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:fuji_san/camera/camera.dart';
import 'package:fuji_san/camera/ptp.dart';
import 'package:fuji_san/camera_diagnosis.dart';

void main() {
  test('descriptor backup failure does not claim recipes were written', () {
    final issue = diagnoseCameraFailure(
      BatchApplyFailure(
        PtpResponseException(0x2002, 0x1014, property: 0xd18c),
        '원본 슬롯 조회',
        false,
        false,
      ),
      '원본 슬롯 백업 중',
    );
    expect(issue.detail, contains('레시피 설정 쓰기는 시작하지 않았습니다'));
    expect(issue.detail, isNot(contains('일부 설정이 적용')));
    expect(issue.title, contains('설정 범위 조회'));
    expect(issue.detail, contains('백업 파일 유무 때문에 발생한 오류는 아닙니다'));
  });
  test(
    'interrupted write identifies saved backup and uncertain partial settings',
    () {
      final issue = diagnoseCameraFailure(
        BatchApplyFailure(
          PlatformException(
            code: 'usb',
            message: 'Send WPD command HRESULT 0x802A0002',
          ),
          'C4 쓰기 및 검증',
          true,
          true,
        ),
        '전송',
      );
      expect(issue.title, contains('연결 객체가 종료'));
      expect(issue.detail, contains('일부 설정이 적용'));
      expect(issue.action, contains('자동 재전송하지 않습니다'));
    },
  );
  test('durable storage failure is distinct from camera communication', () {
    final issue = diagnoseCameraFailure(
      BatchApplyFailure(StateError('disk full'), '백업 파일 저장', false, false),
      '백업',
    );
    expect(issue.title, '백업 파일을 저장하지 못했습니다');
    expect(issue.detail, contains('쓰기는 시작하지 않았습니다'));
  });
}
