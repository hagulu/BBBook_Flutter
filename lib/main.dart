import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/api_config.dart';

void main() {
  ApiConfig.assertConfiguredForRelease();
  runApp(const ProviderScope(child: BBBookApp()));
}
