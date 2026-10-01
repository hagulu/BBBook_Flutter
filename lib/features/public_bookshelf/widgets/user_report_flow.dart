import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../auth/providers/auth_notifier.dart';
import '../../book_detail/providers/book_detail_providers.dart';
import '../../book_detail/screens/widgets/report_dialog.dart';
import '../services/user_report_policy.dart';

/// 현재 계정이 [userId] 사용자를 신고할 수 있는지.
bool canReportUserNow(ProviderContainer container, int userId) {
  final auth = container.read(authNotifierProvider);
  return canReportUser(
    isLoggedIn: auth.isLoggedIn,
    myUserId: auth.user?.id,
    targetUserId: userId,
  );
}

/// 콘텐츠 신고와 같은 신고 모달·`POST /api/reports`로 사용자(USER)를 신고한다.
Future<void> reportUser(BuildContext context, int userId) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final submission = await showReportDialog(context, allowSpoiler: false);
  if (submission == null) return;
  try {
    await container
        .read(bookDetailApiProvider)
        .postReport(
          targetType: 'USER',
          targetId: userId,
          reason: submission.reason.apiValue,
          content: submission.content,
        );
    if (context.mounted) AppSnackBar.success(context, '신고가 접수되었습니다.');
  } on ApiException catch (e) {
    if (context.mounted) AppSnackBar.error(context, e.message);
  }
}
