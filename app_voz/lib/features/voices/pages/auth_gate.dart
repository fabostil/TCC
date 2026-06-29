import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import '../services/auth_session_service.dart';
import '../services/auth_startup_service.dart';
import 'login_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.authSessionService,
    this.loginBuilder,
    this.homeBuilder,
  });

  final AuthSessionService authSessionService;
  final WidgetBuilder? loginBuilder;
  final Widget Function(Usuario usuario)? homeBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<AuthStartupResult> _startup;

  @override
  void initState() {
    super.initState();
    _startup = AuthStartupService(
      sessionService: widget.authSessionService,
    ).resolve();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthStartupResult>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final usuario = snapshot.data?.usuario;
        if (usuario != null) {
          final homeBuilder = widget.homeBuilder;
          if (homeBuilder == null) {
            throw StateError(
              'AuthGate requires homeBuilder for valid session.',
            );
          }
          return homeBuilder(usuario);
        }

        return widget.loginBuilder?.call(context) ?? const LoginPage();
      },
    );
  }
}
