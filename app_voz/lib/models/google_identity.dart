/// Identidade externa retornada pelo provedor Google.
///
/// O [idToken] e preservado para validacao futura por backend/Firebase Auth,
/// mas nao e validado server-side nesta etapa.
class GoogleIdentity {
  const GoogleIdentity({
    required this.nome,
    required this.email,
    required this.googleId,
    required this.idToken,
    this.fotoUrl,
  });

  final String nome;
  final String email;
  final String googleId;
  final String? fotoUrl;
  final String idToken;
}
