import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_controller.dart';
import 'features/onboarding/pages/app_entry_gate.dart';
import 'features/onboarding/pages/microphone_permission_page.dart';
import 'features/voices/coordination/voice_route_observer.dart';
import 'features/voices/pages/auth_gate.dart';
import 'features/voices/services/auth_session_service.dart';
import 'models/usuario.dart';
import 'repositories/configuracao_app_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeController = AppThemeController.instance;
  await themeController.carregarTemaPersistido();

  runApp(VoiceApp(themeController: themeController));
}

class VoiceApp extends StatelessWidget {
  const VoiceApp({
    super.key,
    required this.themeController,
    this.authSessionService,
    this.loginBuilder,
    this.homeBuilder,
  });

  final AppThemeController themeController;
  final AuthSessionService? authSessionService;
  final WidgetBuilder? loginBuilder;
  final Widget Function(Usuario usuario)? homeBuilder;

  Widget _defaultHomeBuilder(Usuario usuario) {
    return homeBuilder?.call(usuario) ??
        MicrophonePermissionPage(
          usuario: usuario,
          salvarResultadoPermissao:
              ConfiguracaoAppRepository.instance.concluirPrimeiraExecucao,
        );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Touchless',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeController.themeMode,
          navigatorObservers: [voiceRouteObserver],
          home: AuthGate(
            authSessionService:
                authSessionService ?? AuthSessionService.instance,
            loginBuilder: loginBuilder ??
                (_) => AppEntryGate(homeBuilder: _defaultHomeBuilder),
            homeBuilder: _defaultHomeBuilder,
          ),
        );
      },
    );
  }
}
