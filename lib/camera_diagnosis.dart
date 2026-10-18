import 'package:flutter/services.dart';

import 'camera/camera.dart';
import 'camera/ptp.dart';
import 'domain/recipe.dart';

class CameraDiagnosis {
  const CameraDiagnosis(this.title, this.detail, this.action);
  final String title, detail, action;
  Map<String, String> toJson() => {
    'title': title,
    'detail': detail,
    'action': action,
  };
}

CameraDiagnosis diagnoseCameraFailure(Object error, String stage) {
  final batch = error is BatchApplyFailure ? error : null;
  final cause = batch?.cause ?? error;
  final phase = batch?.stage ?? stage;
  final state = batch == null
      ? ''
      : batch.writeAttempted
      ? '\n일부 설정이 적용되었을 수 있습니다. 저장된 원본 백업으로 복원할 수 있습니다.'
      : '\n이번 작업의 레시피 설정 쓰기는 시작하지 않았습니다.';
  if (cause is PtpResponseException) {
    final property = cause.property;
    final matches = settings.where((s) => s.id == property);
    final field = property == 0xd18c
        ? 'C 슬롯 선택'
        : property == 0xd18d
        ? '레시피 이름'
        : matches.isNotEmpty
        ? matches.first.label
        : '카메라 설정';
    if (cause.operation == 0x1014) {
      return CameraDiagnosis(
        '설정 범위 조회를 카메라가 거부했습니다',
        '$phase 단계에서 $field의 수정 가능 여부·허용 범위를 조회하지 못했습니다. '
            '백업 파일 유무 때문에 발생한 오류는 아닙니다. '
            '이 응답만으로 연결 모드나 펌웨어 중 어느 것이 원인인지 확정할 수 없습니다.$state',
        '연결 모드를 이미 맞췄다면, 아래 보고서의 기종·펌웨어·앱 버전을 확인하고 카메라 호환성 진단 결과와 함께 확인하세요. X-M5는 펌웨어 버전 대신 속성과 설정값을 검사합니다. 그 외 카메라의 확인되지 않은 제한이나 다른 응답 오류는 자동으로 우회하지 않습니다.',
      );
    }
    if (cause.code == 0x2019) {
      return CameraDiagnosis(
        '카메라가 사용 중입니다',
        '$phase 단계에서 카메라가 사용 중 응답을 보냈습니다.$state',
        '촬영·재생을 마치고 다른 카메라 프로그램을 종료한 뒤 다시 연결하세요.',
      );
    }
    return CameraDiagnosis(
      '카메라가 명령을 거부했습니다',
      '$phase 단계에서 $field 명령이 실패했습니다. 응답 0x${cause.code.toRadixString(16)}만으로 구체적인 원인은 확정할 수 없습니다.$state',
      '카메라 상태와 해당 설정값을 확인하세요. 쓰기 실패는 자동 재전송하지 않습니다.',
    );
  }
  if (cause is PlatformException ||
      '$cause'.contains('USB 연결') ||
      '$cause'.contains('USB 세션')) {
    final shutdown = '$cause'.toLowerCase().contains('0x802a0002');
    return CameraDiagnosis(
      shutdown ? 'Windows 카메라 연결 객체가 종료됐습니다' : 'USB 통신에 실패했습니다',
      '$phase 단계에서 ${shutdown ? '종료된 Windows 연결로 명령을 보낼 수 없었습니다' : '카메라와 명령을 주고받지 못했습니다'}. '
          '케이블·카메라 전원·다른 프로그램 중 어느 것이 원인인지 이 오류만으로 확정할 수 없습니다.$state',
      '카메라 전원과 USB 연결을 확인한 뒤 카메라 연결을 다시 누르세요. 쓰기 중 실패한 작업은 자동 재전송하지 않습니다.',
    );
  }
  if (phase.contains('백업') && phase.contains('저장')) {
    return CameraDiagnosis(
      '백업 파일을 저장하지 못했습니다',
      '카메라 원본을 읽었지만 PC에 백업을 저장하지 못했습니다.$state',
      '저장 공간과 앱 데이터 폴더 쓰기 권한을 확인하세요. 백업이 저장되기 전에는 레시피를 전송하지 않습니다.',
    );
  }
  return CameraDiagnosis(
    '작업을 완료하지 못했습니다',
    '$phase 단계에서 실패했습니다.$state',
    '아래 상세 오류를 확인하세요. 원인을 확인할 수 없는 경우 임의로 카메라 설정을 바꾸거나 전송을 반복하지 않습니다.',
  );
}
