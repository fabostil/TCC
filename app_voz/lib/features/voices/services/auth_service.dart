import '../../../models/google_identity.dart';
import '../../../models/usuario.dart';
import '../../../repositories/usuario_repository.dart';
import 'google_auth_service.dart';

/// Orquestra autenticacao local e conversao de identidade externa em usuario.
///
/// O GoogleAuthService autentica apenas no provedor Google; este servico
/// transforma a identidade retornada em sessao/usuario local persistido.
class AuthService {
  AuthService({
    Future<GoogleIdentity?> Function()? googleIdentityProvider,
    Future<Usuario> Function({
      required String nome,
      required String email,
      required String googleId,
      String? fotoUrl,
    })?
    googleUserResolver,
    Future<Usuario?> Function({required String email, required String senha})?
    localAuthenticator,
    Future<bool> Function({
      required String nome,
      required String email,
      required String senha,
    })?
    localRegister,
  }) : _googleIdentityProvider = googleIdentityProvider,
       _googleUserResolver = googleUserResolver,
       _localAuthenticator = localAuthenticator,
       _localRegister = localRegister;

  static final AuthService instance = AuthService();

  final Future<GoogleIdentity?> Function()? _googleIdentityProvider;
  final Future<Usuario> Function({
    required String nome,
    required String email,
    required String googleId,
    String? fotoUrl,
  })?
  _googleUserResolver;
  final Future<Usuario?> Function({
    required String email,
    required String senha,
  })?
  _localAuthenticator;
  final Future<bool> Function({
    required String nome,
    required String email,
    required String senha,
  })?
  _localRegister;

  /// Entra com Google e resolve a identidade externa para um usuario local.
  ///
  /// O idToken fica preservado em GoogleIdentity para validacao futura por
  /// backend, mas a persistencia local continua em UsuarioRepository.
  Future<Usuario?> entrarComGoogle() async {
    final identityProvider =
        _googleIdentityProvider ?? GoogleAuthService.instance.entrarComGoogle;
    final identity = await identityProvider();

    if (identity == null) {
      return null;
    }

    final resolver =
        _googleUserResolver ?? UsuarioRepository.instance.autenticarComGoogle;
    return resolver(
      nome: identity.nome,
      email: identity.email,
      googleId: identity.googleId,
      fotoUrl: identity.fotoUrl,
    );
  }

  Future<Usuario?> autenticarUsuario({
    required String email,
    required String senha,
  }) {
    final authenticator =
        _localAuthenticator ?? UsuarioRepository.instance.autenticarUsuario;
    return authenticator(email: email, senha: senha);
  }

  Future<bool> cadastrarUsuario({
    required String nome,
    required String email,
    required String senha,
  }) {
    final register =
        _localRegister ?? UsuarioRepository.instance.cadastrarUsuario;
    return register(nome: nome, email: email, senha: senha);
  }
}
