class Usuario {
  final int? id;
  final String nome;
  final String email;
  final String senhaHash;

  Usuario({
    this.id,
    required this.nome,
    required this.email,
    required this.senhaHash,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'nome': nome, 'email': email, 'senha_hash': senhaHash};
  }

  factory Usuario.fromMap(Map<String, dynamic> map) {
    return Usuario(
      id: map['id'] as int?,
      nome: map['nome'] as String,
      email: map['email'] as String,
      senhaHash: map['senha_hash'] as String,
    );
  }

  @override
  String toString() {
    return 'Usuario(id: $id, nome: $nome, email: $email)';
  }
}
