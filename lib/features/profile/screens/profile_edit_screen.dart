import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/patch_field.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/image/services/image_gallery_picker.dart';
import '../../../shared/widgets/app_bar_title.dart';
import '../../../shared/widgets/app_confirm.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/record_dialog_shell.dart';
import '../../auth/providers/auth_notifier.dart';
import '../providers/profile_providers.dart';

/// 프로필 수정 화면(`docs/porting-reference/profile-edit-screen.md`).
///
/// 프로필 메인 화면의 프로필 카드를 탭하면 진입한다.
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _nicknameController = TextEditingController();

  bool _loading = true;
  bool _isSaving = false;
  bool _isDeletingAccount = false;
  String? _nicknameError;

  String _initialNickname = '';
  String? _email;

  /// 서버에 이미 저장된 이미지 URL(§1-1 "현재 표시 중인 이미지" 판단 기준).
  String? _serverImageUrl;

  /// 새로 선택했지만 아직 업로드하지 않은 로컬 이미지.
  File? _pendingImageFile;

  /// "사진 삭제"가 선택된 상태(저장 시 `profileImageUrl: null` 반영 대상).
  bool _imageRemoved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  bool get _hasDisplayedImage =>
      _pendingImageFile != null || (_serverImageUrl != null && !_imageRemoved);

  bool get _busy => _isSaving || _isDeletingAccount;

  Future<void> _load() async {
    try {
      final profile = await ref.read(profileApiProvider).getMyProfile();
      if (!mounted) return;
      setState(() {
        _nicknameController.text = profile.nickname ?? '';
        _initialNickname = profile.nickname ?? '';
        _email = profile.email;
        _serverImageUrl = profile.profileImageUrl;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // 인증 실패(401)는 ApiClient의 refresh→실패 시 로그아웃 흐름이 이미
      // 전역으로 처리하며, 그 결과로 라우터가 루트로 리다이렉트하며 이 화면도
      // 함께 정리된다(§2, CLAUDE.md 인증 API 호출 규칙). 그 외 실패만 이
      // 화면 책임으로 토스트 + 뒤로가기 처리한다.
      if (!e.isAuthFailure) {
        AppSnackBar.error(context, '저장에 실패했습니다');
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _onAvatarTap() async {
    if (_busy) return;
    if (!_hasDisplayedImage) {
      await _pickImage();
      return;
    }
    await _showImageActionSheet();
  }

  Future<void> _showImageActionSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => RecordDialogShell(
        title: '프로필 사진',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RecordDialogActionTile(
              icon: PhosphorIconsRegular.image,
              label: '사진 변경',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickImage();
              },
            ),
            RecordDialogActionTile(
              icon: PhosphorIconsRegular.trash,
              label: '사진 삭제',
              destructive: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _removeImage();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final path = await pickImageFromGallery();
    if (path == null || !mounted) return;
    final error = await validateImageFile(path);
    if (!mounted) return;
    if (error != null) {
      AppSnackBar.error(context, error);
      return;
    }
    setState(() {
      _pendingImageFile = File(path);
      _imageRemoved = false;
    });
  }

  void _removeImage() {
    setState(() {
      _pendingImageFile = null;
      _imageRemoved = true;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final trimmed = _nicknameController.text.trim();
    setState(() => _nicknameError = null);
    if (trimmed.isEmpty) {
      setState(() => _nicknameError = '닉네임을 입력해주세요');
      return;
    }
    if (trimmed.length > 50) {
      setState(() => _nicknameError = '닉네임은 50자 이내로 입력해주세요');
      return;
    }

    final nicknameChanged = trimmed != _initialNickname;
    final imageChanged = _pendingImageFile != null || _imageRemoved;
    if (!nicknameChanged && !imageChanged) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isSaving = true);
    try {
      PatchField<String>? profileImageUrlField;
      if (_pendingImageFile != null) {
        final String uploadedUrl;
        try {
          uploadedUrl = await ref
              .read(profileApiProvider)
              .postProfileImage(_pendingImageFile!);
        } on ApiException catch (e) {
          if (!e.isAuthFailure && mounted) {
            AppSnackBar.error(context, '이미지 업로드에 실패했습니다');
          }
          return;
        }
        profileImageUrlField = PatchField.value(uploadedUrl);
      } else if (_imageRemoved) {
        profileImageUrlField = const PatchField.clear();
      }

      await ref
          .read(profileApiProvider)
          .patchMyProfile(
            nickname: nicknameChanged ? trimmed : null,
            profileImageUrl: profileImageUrlField,
          );
      if (!mounted) return;
      ref.invalidate(profileMeProvider);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!e.isAuthFailure && mounted) {
        AppSnackBar.error(context, '저장에 실패했습니다');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteAccount() async {
    if (_busy) return;
    final confirmed = await AppConfirm.show(
      context,
      title: '정말 탈퇴하시겠습니까?',
      message: '탈퇴하면 모든 독서 기록과 데이터가 영구적으로 삭제됩니다. 이 작업은 되돌릴 수 없습니다.',
      confirmText: '탈퇴하기',
      cancelText: '취소',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      await ref.read(profileApiProvider).deleteMe();
      if (!mounted) return;
      // 서버가 이미 리프레시 토큰을 만료시켰으므로, 로그아웃 API 호출 실패
      // 여부와 무관하게 로컬 인증 상태·서재 캐시를 정리한다(logout()의
      // try/finally가 보장). 라우터가 상태 변화를 감지해 루트로 이동한다.
      await ref.read(authNotifierProvider.notifier).logout();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isDeletingAccount = false);
      AppSnackBar.error(
        context,
        e.statusCode == 403 ? '이미 탈퇴된 계정입니다' : '탈퇴 처리에 실패했습니다',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('프로필 수정'),
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: _AvatarEditor(
                      imageFile: _pendingImageFile,
                      imageUrl: _imageRemoved ? null : _serverImageUrl,
                      nickname: _nicknameController.text,
                      onTap: _busy ? null : _onAvatarTap,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const _FieldLabel('닉네임'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nicknameController,
                    maxLength: 50,
                    enabled: !_busy,
                    // 이미지가 없을 때 기본 아바타 글자가 이 입력값을 그대로
                    // 따라가므로(_AvatarEditor), 에러 초기화 여부와 무관하게
                    // 항상 다시 그린다.
                    onChanged: (_) => setState(() => _nicknameError = null),
                    decoration: InputDecoration(
                      hintText: '닉네임을 입력하세요',
                      counterText: '',
                      errorText: _nicknameError,
                    ),
                  ),
                  if (_email != null) ...[
                    const SizedBox(height: 18),
                    const _FieldLabel('이메일'),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _email!,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '이메일은 변경할 수 없습니다',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _busy ? null : _save,
                    child: _isSaving
                        ? const _ButtonSpinnerLabel(label: '저장 중...')
                        : const Text('저장'),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : _deleteAccount,
                      child: Text(
                        '회원 탈퇴',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
    );
  }
}

class _ButtonSpinnerLabel extends StatelessWidget {
  const _ButtonSpinnerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.textStrong,
          ),
        ),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.imageFile,
    required this.imageUrl,
    required this.nickname,
    required this.onTap,
  });

  final File? imageFile;
  final String? imageUrl;
  final String nickname;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const size = 88.0;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size + 8,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: SizedBox(width: size, height: size, child: _image()),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: AppColors.accentFill,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  PhosphorIconsRegular.camera,
                  size: 15,
                  color: AppColors.textStrong,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _image() {
    if (imageFile != null) {
      return Image.file(imageFile!, fit: BoxFit.cover);
    }
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _initial(),
      );
    }
    return _initial();
  }

  Widget _initial() {
    return ColoredBox(
      color: AppColors.accentSurface,
      child: Center(
        child: Text(
          nickname.isEmpty ? '?' : nickname[0].toUpperCase(),
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.accentForeground,
          ),
        ),
      ),
    );
  }
}
