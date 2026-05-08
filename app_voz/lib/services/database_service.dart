import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/usuario.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();

  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'assistente_musical.db');

    return await openDatabase(path, version: 1, onCreate: _createDatabase);
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE usuario (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        senha_hash TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE gravacao (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        nome TEXT NOT NULL,
        caminho_arquivo TEXT NOT NULL,
        data_criacao TEXT NOT NULL,
        duracao_segundos INTEGER DEFAULT 0,
        FOREIGN KEY (usuario_id) REFERENCES usuario(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE comando_voz (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        comando TEXT NOT NULL,
        acao_executada TEXT NOT NULL,
        data_execucao TEXT NOT NULL,
        FOREIGN KEY (usuario_id) REFERENCES usuario(id)
      )
    ''');
  }

  String gerarHashSenha(String senha) {
    final bytes = utf8.encode(senha);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<bool> cadastrarUsuario({
    required String nome,
    required String email,
    required String senha,
  }) async {
    final db = await database;

    final emailFormatado = email.trim().toLowerCase();

    final usuariosExistentes = await db.query(
      'usuario',
      where: 'email = ?',
      whereArgs: [emailFormatado],
    );

    if (usuariosExistentes.isNotEmpty) {
      return false;
    }

    final usuario = Usuario(
      nome: nome.trim(),
      email: emailFormatado,
      senhaHash: gerarHashSenha(senha),
    );

    await db.insert('usuario', usuario.toMap());

    return true;
  }

  Future<Usuario?> autenticarUsuario({
    required String email,
    required String senha,
  }) async {
    final db = await database;

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
}
