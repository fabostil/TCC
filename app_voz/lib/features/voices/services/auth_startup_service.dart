import '../../../models/usuario.dart';
import 'auth_session_service.dart';

class AuthStartupResult {
  const AuthStartupResult._({required this.usuario});

  final Usuario? usuario;

  bool get authenticated => usuario != null;

  const AuthStartupResult.authenticated(Usuario usuario)
    : this._(usuario: usuario);

  const AuthStartupResult.unauthenticated() : this._(usuario: null);
}

class AuthStartupService {
  const AuthStartupService({required AuthSessionService sessionService})
    : _sessionService = sessionService;

  final AuthSessionService _sessionService;

  Future<AuthStartupResult> resolve() async {
    final usuario = await _sessionService.restoreAuthenticatedUser();
    if (usuario == null) {
      return const AuthStartupResult.unauthenticated();
    }

    return AuthStartupResult.authenticated(usuario);
  }
}
