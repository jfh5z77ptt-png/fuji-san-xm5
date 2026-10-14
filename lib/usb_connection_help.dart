import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

String usbConnectionInstructions(TargetPlatform platform) {
  final cable = platform == TargetPlatform.iOS
      ? '아이폰과 카메라를 데이터 전송이 가능한 USB-C to USB-C 케이블로 직접 연결하세요. 카메라 전원은 켜 두세요.'
      : platform == TargetPlatform.android
      ? 'USB Host/OTG를 지원하는 폰과 카메라를 데이터 케이블로 직접 연결하세요. 카메라 전원은 켜 두세요.'
      : '컴퓨터와 카메라를 데이터 케이블로 직접 연결하세요. 카메라 전원은 켜 두세요.';
  final permission = switch (platform) {
    TargetPlatform.iOS =>
      '카메라 제어 권한 요청이 나오면 허용하세요. 연결이 안 되면 USB 전원 공급/통신 설정을 SUPPLY OFF/COMM ON으로 바꾸고 케이블을 다시 연결해 보세요.',
    TargetPlatform.android => 'USB 접근 권한 요청이 나오면 허용하세요.',
    TargetPlatform.macOS => '카메라 접근 권한 요청이 나오면 허용하세요.',
    TargetPlatform.windows => 'Windows 기본 WPD 드라이버를 사용합니다.',
    _ => '카메라 접근 권한과 운영체제의 USB 지원을 확인하세요.',
  };
  return '1. 카메라 연결 모드를 USB RAW CONV./BACKUP RESTORE로 설정하세요.\n\n'
      '2. $cable\n\n'
      '3. $permission\n\n'
      '4. FujiSan의 카메라 연결을 누르세요. 한 대면 자동 선택하고, 여러 대면 연결할 기기를 선택합니다. 기종·펌웨어 확인 → 설정 조회 검사 → 원본 슬롯 백업 → 백업 파일 저장이 자동으로 진행됩니다. 준비 완료 표시 후 적용하세요.\n\n'
      'USB 전송에는 Wi-Fi·Bluetooth 페어링이 필요하지 않습니다. 다른 카메라 프로그램이 연결을 사용하고 있다면 종료하세요.';
}

Future<void> showUsbConnectionHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('USB로 카메라 연결'),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(usbConnectionInstructions(defaultTargetPlatform)),
          const SizedBox(height: 20),
          const Text(
            '사진을 고른 뒤 전송하기',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '내장 레시피에서 샘플 사진을 보고 라이브러리에 추가하세요. '
            'C 슬롯 화면에서 레시피를 배치하고 적용할 슬롯을 선택한 뒤 일괄 적용을 누르세요. '
            '연결 없이 레시피를 탐색·배치할 수 있습니다. 연결 없이 적용을 누르면 먼저 연결하도록 안내합니다. 전송 직전에 연결과 설정 범위를 다시 확인하고 기존 설정을 새로 백업한 후 전송하고 카메라 값을 다시 읽어 확인합니다.\n\n'
            'X-M5는 C1–C4, X-T5는 C1–C7입니다. 아이폰 실기 전송은 아직 검증되지 않았습니다.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
    ],
  ),
);
