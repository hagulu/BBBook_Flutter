import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../app/main_shell_layout.dart';
import '../../auth/providers/auth_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_loading.dart';
import '../../auth/providers/auth_access_providers.dart';
import '../../auth/providers/auth_notifier.dart';
import '../../auth/screens/onboarding_screen.dart';
import '../../auth/widgets/social_login_section.dart';
import '../../record_sync/providers/logout_record_sync_provider.dart';
import '../../storage_mode/providers/storage_mode_providers.dart';
import '../models/profile_me.dart';
import '../models/profile_stats_summary.dart';
import '../providers/profile_providers.dart';
import 'my_discussion_answers_screen.dart';
import 'my_discussions_screen.dart';
import 'my_reflections_screen.dart';
import 'my_reviews_screen.dart';
import 'profile_edit_screen.dart';
import 'reading_stats_screen.dart';

/// 프로필(개인 페이지) 메인 화면(`docs/porting-reference/profile-main-screen.md`).
///
/// 저장 방식(서버/로컬) 전환 등 포팅 문서 범위 밖의 기능은 이 화면이 아니라
/// [MainShell]의 프로필 탭 전용 설정 아이콘 → 별도 설정 화면에 둔다.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 계정이 없으면 서버 프로필도, 내가 쓴 공개 글도 없다. 상단만 로그인
    // 유도로 바꾸고 로컬 데이터로 만들 수 있는 독서 리포트는 그대로 둔다.
    if (!ref.watch(canUseAccountFeaturesProvider)) {
      return const _StandaloneProfileContent();
    }

    final profileAsync = ref.watch(profileMeProvider);
    final user = ref.watch(authNotifierProvider.select((auth) => auth.user));
    final localProfile = user == null
        ? null
        : ProfileMe(
            id: user.id,
            nickname: user.nickname,
            email: null,
            profileImageUrl: user.profileImageUrl,
          );

    return profileAsync.when(
      loading: () => localProfile == null
          ? const _CenteredMessage(text: '불러오는 중...')
          : _ProfileContent(profile: localProfile),
      error: (error, stackTrace) => localProfile != null
          ? _ProfileContent(profile: localProfile)
          : _CenteredMessage(
              text: '프로필을 불러오지 못했습니다',
              action: TextButton(
                onPressed: () {
                  ref.read(apiClientProvider).requestUserRetry();
                  ref.invalidate(profileMeProvider);
                },
                child: const Text('다시 시도'),
              ),
            ),
      data: (profile) => _ProfileContent(profile: profile),
    );
  }
}

/// 로그인하지 않고 쓰는 사용자의 MY 화면.
///
/// 기존 프로필 카드 자리를 로그인 유도로 바꾸고(요구사항 6), 서버 계정을
/// 전제로 하는 "내 글 모아보기"와 로그아웃은 감춘다. 독서 리포트는 로컬
/// 서재 데이터로만 계산하므로 그대로 보여준다.
class _StandaloneProfileContent extends StatelessWidget {
  const _StandaloneProfileContent();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MainShellNavigationLayout.contentBottomPadding(context),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_LoginPromptCard(), SizedBox(height: 16), _StatsCard()],
      ),
    );
  }
}

/// 프로필 영역 자리에 들어가는 로그인 유도 카드. 별도의 큰 로그인 전용
/// 영역을 만들지 않고, 안내 한 줄 + 소셜 로그인 버튼만 간결하게 둔다.
class _LoginPromptCard extends StatelessWidget {
  const _LoginPromptCard();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return _SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: colors.accentSurface,
                child: Icon(
                  PhosphorIconsRegular.userCircle,
                  size: 22,
                  color: colors.accentForeground,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '로그인하고 더 많은 기능을 사용해보세요',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '기록 동기화, 독자평·토론 참여를 쓸 수 있습니다.',
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SocialLoginSection(compact: true),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: TextStyle(color: AppColors.of(context).textMuted)),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

class _ProfileContent extends ConsumerWidget {
  const _ProfileContent({required this.profile});

  final ProfileMe profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requiresLogin = ref.watch(
      authNotifierProvider.select((auth) => auth.requiresLogin),
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MainShellNavigationLayout.contentBottomPadding(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileCard(profile: profile),
          if (requiresLogin) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const OnboardingScreen(reauthentication: true),
                ),
              ),
              icon: const Icon(PhosphorIconsRegular.signIn),
              label: const Text('기록 동기화를 위해 다시 로그인'),
            ),
          ],
          const SizedBox(height: 16),
          const _StatsCard(),
          const SizedBox(height: 16),
          const _MyContentCard(),
          const SizedBox(height: 20),
          const _LogoutButton(),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final ProfileMe profile;

  @override
  Widget build(BuildContext context) {
    final nickname = profile.nickname ?? '사용자';
    return Semantics(
      button: true,
      label: '프로필 수정',
      excludeSemantics: true,
      child: Material(
        color: AppColors.of(context).pageBackground,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ProfileEditScreen()),
          ),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                _Avatar(
                  imageUrl: profile.profileImageUrl,
                  nickname: nickname,
                  size: 76,
                ),
                const SizedBox(height: 10),
                Text(
                  nickname,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.of(context).textStrong,
                  ),
                ),
                if (profile.email != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    profile.email!,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.of(context).textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.imageUrl,
    required this.nickname,
    this.size = 56,
  });

  final String? imageUrl;
  final String nickname;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: AppColors.of(context).accentSurface,
        child: Text(
          _initialOf(nickname),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.of(context).accentForeground,
          ),
        ),
      );
    }
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => CircleAvatar(
          radius: size / 2,
          backgroundColor: AppColors.of(context).accentSurface,
          child: Text(
            _initialOf(nickname),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.of(context).accentForeground,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsCard extends ConsumerWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(profileStatsSummaryProvider);

    // 카드 전체가 하나의 시맨틱스 버튼으로 묶이면서(_SectionCard) 내부 값의
    // 시맨틱스는 제외되므로(다른 탭 이동 카드들과 동일한 관례), 완독
    // 권수·읽은 페이지·많이 읽은 분야 값을 라벨에 함께 담아 스크린 리더에서도
    // 읽히게 한다.
    final semanticsLabel = statsAsync.when(
      loading: () => '독서 리포트, 불러오는 중',
      error: (error, stackTrace) => '독서 리포트, 불러오지 못했습니다',
      data: (stats) =>
          '독서 리포트, 완독 ${_formatThousands(stats.finishedCount)}권, '
          '읽은 페이지 ${_formatThousands(stats.totalPages)}페이지, '
          '많이 읽은 분야 ${stats.mostReadCategory?.categoryName ?? '없음'}',
    );

    return _SectionCard(
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const ReadingStatsScreen()),
      ),
      semanticsLabel: semanticsLabel,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '독서 리포트',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: AppColors.of(context).textMuted,
                ),
              ),
              Icon(
                PhosphorIconsRegular.caretRight,
                size: 16,
                color: AppColors.of(context).textMuted,
              ),
            ],
          ),
          const SizedBox(height: 14),
          statsAsync.when(
            loading: () => const _StatsPlaceholder(text: '불러오는 중...'),
            error: (error, stackTrace) =>
                const _StatsPlaceholder(text: '리포트를 불러오지 못했습니다'),
            data: (stats) => _StatsRow(stats: stats),
          ),
        ],
      ),
    );
  }
}

class _StatsPlaceholder extends StatelessWidget {
  const _StatsPlaceholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: AppColors.of(context).textMuted),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final ProfileStatsSummary stats;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _StatsColumn(
              value: _formatThousands(stats.finishedCount),
              unit: '권',
              label: '완독',
            ),
          ),
          VerticalDivider(width: 1, color: AppColors.of(context).border),
          Expanded(
            child: _StatsColumn(
              value: _formatThousands(stats.totalPages),
              unit: 'p',
              label: '읽은 페이지',
            ),
          ),
          VerticalDivider(width: 1, color: AppColors.of(context).border),
          Expanded(
            child: _StatsColumn(
              value: stats.mostReadCategory?.categoryName ?? '–',
              label: '많이 읽은 분야',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsColumn extends StatelessWidget {
  const _StatsColumn({required this.value, this.unit, required this.label});

  final String value;
  final String? unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.of(context).textStrong,
                ),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 1),
              Text(
                unit!,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.of(context).textMuted,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.of(context).textMuted,
          ),
        ),
      ],
    );
  }
}

class _MyContentCard extends StatelessWidget {
  const _MyContentCard();

  @override
  Widget build(BuildContext context) {
    final labelHeight = MediaQuery.textScalerOf(context).scale(14) * 1.4;
    final itemHeight = 70 + labelHeight;
    final shortcuts = [
      _ContentShortcutButton(
        icon: PhosphorIconsRegular.fileText,
        label: '독후감',
        semanticsLabel: '내가 작성한 독후감',
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const MyReflectionsScreen()),
        ),
      ),
      _ContentShortcutButton(
        icon: PhosphorIconsRegular.star,
        label: '독자평',
        semanticsLabel: '내가 작성한 독자평',
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const MyReviewsScreen()),
        ),
      ),
      _ContentShortcutButton(
        icon: PhosphorIconsRegular.chat,
        label: '토론',
        semanticsLabel: '내가 작성한 토론',
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const MyDiscussionsScreen()),
        ),
      ),
      _ContentShortcutButton(
        icon: PhosphorIconsRegular.chatCircle,
        label: '토론 댓글',
        semanticsLabel: '내가 작성한 토론 댓글',
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const MyDiscussionAnswersScreen()),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '내 글 모아보기',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: AppColors.of(context).textMuted,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: itemHeight,
          ),
          itemCount: shortcuts.length,
          itemBuilder: (context, index) => shortcuts[index],
        ),
      ],
    );
  }
}

class _ContentShortcutButton extends StatelessWidget {
  const _ContentShortcutButton({
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      onTap: onTap,
      semanticsLabel: semanticsLabel,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.of(context).accentSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SizedBox.square(
              dimension: 36,
              child: Icon(
                icon,
                size: 19,
                color: AppColors.of(context).accentForeground,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.of(context).textStrong,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutButton extends ConsumerWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.center,
      child: TextButton(
        onPressed: () => _logout(context, ref),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.of(context).textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        child: const Text(
          '로그아웃',
          style: TextStyle(fontSize: 12, decoration: TextDecoration.underline),
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    // 로그아웃 시 로컬 데이터 처리는 저장 방식을 따른다
    // (auth_notifier.dart의 logout()). 두 경우의 결과가 정반대라 무엇이
    // 남고 무엇이 사라지는지 먼저 정확히 알려야 한다.
    // - 로컬 저장: 서버에 사본이 없는 유일본이라 기록을 지우지 않고 계정
    //   연결만 끊는다. 이후 "로그인 없이 사용하기"로 그대로 이어 쓴다.
    // - 서버 동기화: 서버 사본이 있으므로 이 기기의 사본을 비운다. 아직
    //   올리지 못한 변경만 복구할 수 없다.
    //
    // storageModeProvider(FutureProvider)를 read해 valueOrNull만 보면, 이
    // 화면 진입 전에 아무도 이 provider를 구독하지 않았을 경우 최초 상태가
    // AsyncLoading이라 실제로 로컬 모드여도 서버 모드용 문구가 뜬다.
    // StorageModeStore.isLocal()을 직접 await해 확정된 값으로 판단한다.
    //
    // 확인 팝업·최종 동기화를 기다리는 사이 이 화면이 제거되면 [ref]를 더
    // 읽을 수 없다. 사용자가 이미 로그아웃을 골랐으므로 흐름이 끊기지 않게
    // 쓸 대상을 먼저 잡아 둔다.
    final auth = ref.read(authNotifierProvider.notifier);
    final logoutSync = ref.read(logoutRecordSyncProvider);
    final isLocal = await ref.read(storageModeStoreProvider).isLocal();
    if (!context.mounted) return;
    final confirmed = await AppConfirm.show(
      context,
      title: '로그아웃',
      message: isLocal
          ? '동기화가 꺼져 있어 기록은 이 기기에만 있습니다. 로그아웃해도 기록과 '
                '사진은 지우지 않고 계정 연결만 해제하며, "로그인 없이 사용하기"로 '
                '다시 들어오면 그대로 이어서 볼 수 있습니다. 로그아웃할까요?'
          : '로그아웃할까요?',
      confirmText: '로그아웃',
      cancelText: '취소',
      destructive: !isLocal,
    );
    if (!confirmed) return;
    if (!isLocal) {
      if (!context.mounted) return;
      if (!await _syncBeforeLogout(context, logoutSync)) return;
    }
    await auth.logout();
  }

  /// 서버 동기화 모드는 로그아웃하며 이 기기의 기록을 지우므로, 그 전에
  /// 마지막 동기화를 시도한다. 그래도 서버에 올리지 못한 기록이 남으면
  /// 로그아웃을 멈추고 다시 시도할지, 기록을 포기하고 로그아웃할지 묻는다.
  /// 팝업을 그냥 닫으면 로그아웃하지 않는다. 계속 진행해도 되면 true.
  Future<bool> _syncBeforeLogout(
    BuildContext context,
    LogoutRecordSync logoutSync,
  ) async {
    while (true) {
      AppLoading.show(context);
      final bool hasUnsynced;
      try {
        hasUnsynced = await logoutSync.syncAndCheckUnsynced();
      } finally {
        AppLoading.hide();
      }
      if (!hasUnsynced) return true;
      if (!context.mounted) return false;
      final forceLogout = await AppConfirm.choose(
        context,
        title: '로그아웃',
        message: '동기화되지 않은 기록이 있습니다. 지금 로그아웃하면 해당 기록이 삭제될 수 있습니다.',
        confirmText: '그래도 로그아웃',
        cancelText: '다시 시도',
        destructive: true,
      );
      if (forceLogout == null) return false;
      if (forceLogout) return true;
      if (!context.mounted) return false;
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
    required this.padding,
    this.onTap,
    this.semanticsLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: onTap == null
          ? ClipRRect(borderRadius: BorderRadius.circular(16), child: content)
          : Semantics(
              button: true,
              label: semanticsLabel,
              excludeSemantics: semanticsLabel != null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InkWell(onTap: onTap, child: content),
              ),
            ),
    );
  }
}

String _initialOf(String nickname) =>
    nickname.isEmpty ? '?' : nickname[0].toUpperCase();

String _formatThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return (value < 0 ? '-' : '') + buffer.toString();
}
