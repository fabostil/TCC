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

  Future<bool> cadastrarUsuario({
    required String nome,
    required String email,
    required String senha,
  }) async {
    final db = await _database;

    final nomeFormatado = nome.trim();
    final emailFormatado = email.trim().toLowerCase();
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

    final emailFormatado = email.trim().toLowerCase();
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
}
