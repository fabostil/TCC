import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_controller.dart';
import 'features/voices/coordination/voice_route_observer.dart';
import 'features/voices/pages/login_page.dart';

final VoiceRouteObserver voiceRouteObserver = VoiceRouteObserver();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeController = AppThemeController.instance;
  await themeController.carregarTemaPersistido();

  runApp(VoiceApp(themeController: themeController));
}

class VoiceApp extends StatelessWidget {
  const VoiceApp({super.key, required this.themeController});

  final AppThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Assistente Musical',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeController.themeMode,
          navigatorObservers: [voiceRouteObserver],
          home: const LoginPage(),
        );
      },
    );
  }
}
