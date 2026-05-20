import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/usuario.dart';

class UsuarioRepository {
  UsuarioRepository._internal();

  static final UsuarioRepository instance = UsuarioRepository._internal();

  Future<Database> get _database async => AppDatabase.instance.database;

  String gerarHashSenha(String senha) {
    final bytes = utf8.encode(senha.trim());
    final digest = sha256.convert(bytes);
    return digest.toString();
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
    final senhaHash = gerarHashSenha(senha);

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
      senhaHash: senhaHash,
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
    final senhaHash = gerarHashSenha(senha);

    final resultado = await db.query(
      'usuario',
      where: 'email = ? AND senha_hash = ?',
      whereArgs: [emailFormatado, senhaHash],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Usuario.fromMap(resultado.first);
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

    final usuario = Usuario(
      nome: nomeFormatado,
      email: emailFormatado,
      senhaHash: gerarHashSenha('google:$googleIdFormatado'),
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
}
