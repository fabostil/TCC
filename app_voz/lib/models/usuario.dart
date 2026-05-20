class Usuario {
  final int? id;
  final String nome;
  final String email;
  final String senhaHash;
  final String authProvider;
  final String? googleId;
  final String? fotoUrl;
  final String? dataCadastro;

  Usuario({
    this.id,
    required this.nome,
    required this.email,
    required this.senhaHash,
    this.authProvider = 'local',
    this.googleId,
    this.fotoUrl,
    this.dataCadastro,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'email': email,
      'senha_hash': senhaHash,
      'auth_provider': authProvider,
      'google_id': googleId,
      'foto_url': fotoUrl,
      'data_cadastro': dataCadastro,
    };
  }

  factory Usuario.fromMap(Map<String, dynamic> map) {
    return Usuario(
      id: map['id'] as int?,
      nome: map['nome'] as String,
      email: map['email'] as String,
      senhaHash: map['senha_hash'] as String,
      authProvider: map['auth_provider'] as String? ?? 'local',
      googleId: map['google_id'] as String?,
      fotoUrl: map['foto_url'] as String?,
      dataCadastro: map['data_cadastro'] as String?,
    );
  }

  @override
  String toString() {
    return 'Usuario(id: $id, nome: $nome, email: $email)';
  }
}
