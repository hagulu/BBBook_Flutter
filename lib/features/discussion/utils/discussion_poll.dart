import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/discussion_topic.dart';

/// 사용자가 직접 만들 수 있는 선택지 최대 개수("기타"는 여기에 포함되지 않는다).
const int kMaxDiscussionOptions = 5;

/// 선택지 내용 최대 길이.
const int kMaxDiscussionOptionLength = 200;

/// 토론 주제 제목 최대 길이.
const int kMaxDiscussionTitleLength = 200;

/// 선택지 순서대로 배정되는 고정 팔레트. 마지막 값은 자동 제공되는 "기타" 전용.
const List<Color> kDiscussionOptionColors = [
  AppColors.pollBlue,
  AppColors.pollPurple,
  AppColors.pollGreen,
  AppColors.pollAmber,
  AppColors.pollPink,
  AppColors.pollGray,
];

/// [index]번째 선택지의 색. 팔레트를 넘어서는 순서(있을 수 없는 값)는 "기타"
/// 색으로 떨어뜨려 화면이 깨지지 않게 한다.
Color discussionOptionColorAt(int index) {
  if (index < 0 || index >= kDiscussionOptionColors.length - 1) {
    return kDiscussionOptionColors.last;
  }
  return kDiscussionOptionColors[index];
}

/// "기타"(optionId == null) 전용 색.
Color get discussionOtherOptionColor => kDiscussionOptionColors.last;

/// 답변 배너/결과 바에서 optionId 하나를 같은 색으로 계속 쓰기 위한 조회.
/// 목록에 없는 id(삭제된 선택지 등)는 "기타" 색으로 처리한다.
Color discussionOptionColorOf(List<DiscussionOption> options, int? optionId) {
  if (optionId == null) return discussionOtherOptionColor;
  final index = options.indexWhere((o) => o.id == optionId);
  return index < 0 ? discussionOtherOptionColor : discussionOptionColorAt(index);
}

/// optionId에 해당하는 선택지 라벨. null이거나 못 찾으면 "기타".
String discussionOptionLabelOf(List<DiscussionOption> options, int? optionId) {
  if (optionId == null) return '기타';
  for (final option in options) {
    if (option.id == optionId) return option.content;
  }
  return '기타';
}

/// 토론 수정 시 선택지 변경이 append-only 제약을 지키는지 검사한다.
///
/// 기존 선택지는 수정·삭제·순서 변경이 불가능하므로, [current]의 앞부분이
/// [initial]과 순서·내용까지 정확히 일치해야만 제출을 허용한다(서버도 같은
/// 규칙으로 400을 반환한다).
bool isDiscussionOptionsAppendOnly(
  List<String> initial,
  List<String> current,
) {
  if (current.length < initial.length) return false;
  for (var i = 0; i < initial.length; i++) {
    if (current[i] != initial[i]) return false;
  }
  return true;
}

/// 퍼센트 표기(소수점 최대 1자리). 정수면 소수점을 붙이지 않는다.
String formatVotePercentage(double value) {
  final rounded = (value * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) return '${rounded.round()}%';
  return '${rounded.toStringAsFixed(1)}%';
}
