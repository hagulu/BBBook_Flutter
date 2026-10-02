import 'package:flutter/material.dart';

import '../../../shared/widgets/app_alert.dart';

/// 징계 중 사용할 수 없는 기능을 눌렀을 때 띄우는 안내 팝업.
///
/// 버튼을 숨기지 않고 노출한 뒤, 징계 상태이면 실행 대신 이 팝업을 보여 준다.
Future<void> showSanctionRestrictedAlert(BuildContext context) {
  return AppAlert.show(
    context,
    title: '징계 안내',
    message: '현재 징계 중이라 이용할 수 없는 기능입니다.\n사유와 기간은 마이 화면의 징계 안내에서 확인할 수 있습니다.',
  );
}
