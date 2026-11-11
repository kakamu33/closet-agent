import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/shell/app_shell.dart';

class DiexuApp extends ConsumerWidget {
  const DiexuApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    return MaterialApp(
      key: ValueKey(session.value?.id ?? 'signed-out'),
      title: '叠序',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: session.when(
        loading: () => const _StartupScreen(),
        error: (error, _) => AuthScreen(key: ValueKey(error)),
        data: (user) => user == null ? const AuthScreen() : const AppShell(),
      ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
