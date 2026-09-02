import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../auth/providers/auth_notifier.dart';
import '../../notices/screens/notices_list_screen.dart';
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
    final profileAsync = ref.watch(profileMeProvider);

    return profileAsync.when(
      loading: () => const _CenteredMessage(text: '불러오는 중...'),
      error: (error, stackTrace) => _CenteredMessage(
        text: '프로필을 불러오지 못했습니다',
        action: TextButton(
          onPressed: () => ref.invalidate(profileMeProvider),
          child: const Text('다시 시도'),
        ),
      ),
      data: (profile) => _ProfileContent(profile: profile),
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
          Text(text, style: const TextStyle(color: AppColors.textMuted)),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.profile});

  final ProfileMe profile;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileCard(profile: profile),
          const SizedBox(height: 16),
          const _StatsCard(),
          const SizedBox(height: 16),
          const _MyContentCard(),
          const SizedBox(height: 16),
          const _NoticesCard(),
          const SizedBox(height: 20),
          const _LogoutButton(),
          const SizedBox(height: 28),
          const _FooterLinks(),
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
    return _SectionCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ProfileEditScreen()),
      ),
      semanticsLabel: '프로필 수정',
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _Avatar(imageUrl: profile.profileImageUrl, nickname: nickname),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textStrong,
                  ),
                ),
                if (profile.email != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    profile.email!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(
            PhosphorIconsRegular.caretRight,
            size: 18,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.imageUrl, required this.nickname});

  final String? imageUrl;
  final String nickname;

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: AppColors.accentSurface,
        child: Text(
          _initialOf(nickname),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.accentForeground,
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
          backgroundColor: AppColors.accentSurface,
          child: Text(
            _initialOf(nickname),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.accentForeground,
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
              const Text(
                '독서 리포트',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: AppColors.textMuted,
                ),
              ),
              const Icon(
                PhosphorIconsRegular.caretRight,
                size: 16,
                color: AppColors.textMuted,
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
        child: Text(text, style: const TextStyle(color: AppColors.textMuted)),
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
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(
            child: _StatsColumn(
              value: _formatThousands(stats.totalPages),
              unit: 'p',
              label: '읽은 페이지',
            ),
          ),
          const VerticalDivider(width: 1, color: AppColors.border),
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
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textStrong,
                ),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 1),
              Text(
                unit!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
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
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '내 글 모아보기',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: AppColors.textMuted,
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
              color: AppColors.accentSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SizedBox.square(
              dimension: 36,
              child: Icon(icon, size: 19, color: AppColors.accentForeground),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticesCard extends StatelessWidget {
  const _NoticesCard();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      padding: EdgeInsets.zero,
      child: _MenuRow(
        icon: PhosphorIconsRegular.megaphone,
        label: '공지사항',
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const NoticesListScreen()),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.accentForeground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textStrong,
                ),
              ),
            ),
            const Icon(
              PhosphorIconsRegular.caretRight,
              size: 16,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutButton extends ConsumerWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _logout(context, ref),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.error,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        icon: const Icon(PhosphorIconsRegular.signOut, size: 18),
        label: const Text('로그아웃'),
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    // 로그아웃은 저장 모드와 무관하게 로컬 DB·사진을 항상 지운다
    // (auth_notifier.dart의 logout()). 로컬 저장 모드는 서버 사본이 없는
    // 유일본이라 그 사실을 먼저 알려야 한다(포팅 문서는 이 앱에만 있는
    // 저장 모드 개념을 다루지 않아 별도로 안내한다).
    //
    // storageModeProvider(FutureProvider)를 read해 valueOrNull만 보면, 이
    // 화면 진입 전에 아무도 이 provider를 구독하지 않았을 경우 최초 상태가
    // AsyncLoading이라 실제로 로컬 모드여도 서버 모드용 문구가 뜬다.
    // StorageModeStore.isLocal()을 직접 await해 확정된 값으로 판단한다.
    final isLocal = await ref.read(storageModeStoreProvider).isLocal();
    if (!context.mounted) return;
    final confirmed = await AppConfirm.show(
      context,
      title: '로그아웃',
      message: isLocal
          ? '로컬 저장 모드입니다. 로그아웃하면 이 기기에 저장된 모든 기록과 사진이 '
                '삭제되며 서버에도 사본이 없어 복구할 수 없습니다. 로그아웃할까요?'
          : '아직 서버에 동기화되지 않은 메모와 사진은 이 기기에서 '
                '삭제되어 복구할 수 없습니다. 로그아웃할까요?',
      confirmText: '로그아웃',
      cancelText: '취소',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(authNotifierProvider.notifier).logout();
  }
}

class _FooterLinks extends StatelessWidget {
  const _FooterLinks();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FooterLink(label: '이용약관', path: '/terms'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              height: 12,
              child: VerticalDivider(width: 1, color: AppColors.border),
            ),
          ),
          _FooterLink(label: '개인정보처리방침', path: '/privacy'),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.path});

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(
        Uri.parse('${ApiConfig.baseUrl}$path'),
        mode: LaunchMode.externalApplication,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    );
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
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
