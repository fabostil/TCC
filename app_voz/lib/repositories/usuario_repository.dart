import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../features/voices/services/password_hash_service.dart';
import '../models/usuario.dart';

class UsuarioNaoEncontradoException implements Exception {
  const UsuarioNaoEncontradoException();

  @override
  String toString() => 'Conta não encontrada.';
}

class UsuarioRepository {
  UsuarioRepository._internal();

  static final UsuarioRepository instance = UsuarioRepository._internal();

  Future<Database> get _database async => AppDatabase.instance.database;

  /// Existe somente para compatibilidade com hashes SHA-256 legados.
  ///
  /// Nao use este metodo para novos cadastros; eles devem usar PBKDF2 via
  /// PasswordHashService.
  String gerarHashSenha(String senha) {
    return PasswordHashService.instance.generateLegacySha256Hash(senha);
  }

  String _normalizarEmail(String email) => email.trim().toLowerCase();

  Future<bool> cadastrarUsuario({
    required String nome,
    required String email,
    required String senha,
  }) async {
    final db = await _database;

    final nomeFormatado = nome.trim();
    final emailFormatado = _normalizarEmail(email);
    final credential = PasswordHashService.instance.hashNewPassword(senha);

    final usuariosExistentes = await db.query(
      'usuario',
      where: 'email = ?',
      whereArgs: [emailFormatado],
      limit: 1,
    );

    if (usuariosExistentes.isNotEmpty) {
      return false;
    }

    final usuario = Usuario(
      nome: nomeFormatado,
      email: emailFormatado,
      senhaHash: credential.senhaHash,
      senhaSalt: credential.senhaSalt,
      senhaAlgoritmo: credential.senhaAlgoritmo,
      senhaIteracoes: credential.senhaIteracoes,
      senhaVersao: credential.senhaVersao,
      authProvider: 'local',
      dataCadastro: DateTime.now().toIso8601String(),
    );

    await db.insert(
      'usuario',
      usuario.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    return true;
  }

  Future<Usuario?> autenticarUsuario({
    required String email,
    required String senha,
  }) async {
    final db = await _database;

    final emailFormatado = _normalizarEmail(email);

    final resultado = await db.query(
      'usuario',
      where: 'email = ?',
      whereArgs: [emailFormatado],
      limit: 1,
    );

    if (resultado.isEmpty) {
      throw const UsuarioNaoEncontradoException();
    }

    final usuario = Usuario.fromMap(resultado.first);
    final senhaValida = PasswordHashService.instance.verifyPassword(
      password: senha,
      usuario: usuario,
    );
    if (!senhaValida) {
      return null;
    }

    if (!PasswordHashService.instance.shouldRehash(usuario)) {
      return usuario;
    }

    final credential = PasswordHashService.instance
        .rehashLegacyPasswordAfterSuccessfulLogin(senha);
    return _atualizarCredencial(db, usuario, credential);
  }

  Future<List<Usuario>> listarUsuarios() async {
    final db = await _database;
    final resultado = await db.query('usuario', orderBy: 'nome ASC');
    return resultado.map((map) => Usuario.fromMap(map)).toList();
  }

  Future<Usuario?> buscarPorEmail(String email) async {
    final db = await _database;
    final resultado = await db.query(
      'usuario',
      where: 'email = ?',
      whereArgs: [_normalizarEmail(email)],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Usuario.fromMap(resultado.first);
  }

  Future<Usuario?> buscarPorId(int id) async {
    final db = await _database;
    final resultado = await db.query(
      'usuario',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Usuario.fromMap(resultado.first);
  }

  Future<Usuario?> buscarPorGoogleId(String googleId) async {
    final db = await _database;
    final resultado = await db.query(
      'usuario',
      where: 'google_id = ?',
      whereArgs: [googleId.trim()],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Usuario.fromMap(resultado.first);
  }

  Future<Usuario> autenticarComGoogle({
    required String nome,
    required String email,
    required String googleId,
    String? fotoUrl,
  }) async {
    final db = await _database;
    final nomeFormatado = nome.trim().isEmpty ? 'Usuario Google' : nome.trim();
    final emailFormatado = _normalizarEmail(email);
    final googleIdFormatado = googleId.trim();

    if (emailFormatado.isEmpty || googleIdFormatado.isEmpty) {
      throw ArgumentError('Conta Google sem identificador valido.');
    }

    final usuarioPorGoogle = await buscarPorGoogleId(googleIdFormatado);
    if (usuarioPorGoogle != null) {
      await db.update(
        'usuario',
        {'nome': nomeFormatado, 'email': emailFormatado, 'foto_url': fotoUrl},
        where: 'id = ?',
        whereArgs: [usuarioPorGoogle.id],
      );
      return (await buscarPorGoogleId(googleIdFormatado))!;
    }

    final usuarioPorEmail = await buscarPorEmail(emailFormatado);
    if (usuarioPorEmail != null) {
      await db.update(
        'usuario',
        {
          'nome': usuarioPorEmail.nome.trim().isEmpty
              ? nomeFormatado
              : usuarioPorEmail.nome,
          'auth_provider': usuarioPorEmail.authProvider == 'local'
              ? 'local_google'
              : usuarioPorEmail.authProvider,
          'google_id': googleIdFormatado,
          'foto_url': fotoUrl,
        },
        where: 'id = ?',
        whereArgs: [usuarioPorEmail.id],
      );
      return (await buscarPorGoogleId(googleIdFormatado))!;
    }

    final credential = PasswordHashService.instance
        .externalProviderCredential();
    final usuario = Usuario(
      nome: nomeFormatado,
      email: emailFormatado,
      senhaHash: credential.senhaHash,
      senhaSalt: credential.senhaSalt,
      senhaAlgoritmo: credential.senhaAlgoritmo,
      senhaIteracoes: credential.senhaIteracoes,
      senhaVersao: credential.senhaVersao,
      authProvider: 'google',
      googleId: googleIdFormatado,
      fotoUrl: fotoUrl,
      dataCadastro: DateTime.now().toIso8601String(),
    );

    final id = await db.insert(
      'usuario',
      usuario.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    final criado = await buscarPorGoogleId(googleIdFormatado);
    if (criado == null) {
      throw StateError('Falha ao carregar usuario Google criado ($id).');
    }

    return criado;
  }

  Future<Usuario> _atualizarCredencial(
    Database db,
    Usuario usuario,
    PasswordHashResult credential,
  ) async {
    await db.update(
      'usuario',
      {
        'senha_hash': credential.senhaHash,
        'senha_salt': credential.senhaSalt,
        'senha_algoritmo': credential.senhaAlgoritmo,
        'senha_iteracoes': credential.senhaIteracoes,
        'senha_versao': credential.senhaVersao,
      },
      where: 'id = ?',
      whereArgs: [usuario.id],
    );

    return (await buscarPorEmail(usuario.email))!;
  }
}
