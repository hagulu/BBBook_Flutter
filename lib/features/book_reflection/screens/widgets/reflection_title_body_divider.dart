import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class ReflectionTitleBodyDivider extends StatelessWidget {
  const ReflectionTitleBodyDivider({super.key, this.horizontalInset = 24});

  final double horizontalInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Divider(
        height: 1,
        thickness: 1,
        indent: horizontalInset,
        endIndent: horizontalInset,
        color: AppColors.border,
      ),
    );
  }
}
