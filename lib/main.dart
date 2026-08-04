import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // 本地凭证文件未配置时仍可启动；CloudBaseConfig 会使用环境 ID 默认值。
  }
  runApp(const ProviderScope(child: DiexuApp()));
}
