import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../../models/usuario.dart';

/// Servico responsavel por criar e verificar credenciais locais de usuario.
///
/// Novos hashes usam PBKDF2-HMAC-SHA256. A compatibilidade SHA-256 existe
/// apenas para autenticar e migrar usuarios criados antes da mudanca.
class PasswordHashService {
  PasswordHashService({List<int> Function(int lengthBytes)? saltGenerator})
    : _saltGenerator = saltGenerator;

  static final PasswordHashService instance = PasswordHashService();

  static const _legacySha256Algorithm = 'sha256_legacy';
  static const _pbkdf2Algorithm = 'pbkdf2_sha256';
  static const _externalProviderAlgorithm = 'external_provider';
  static const _externalProviderPasswordHash = 'external_provider';
  static const _pbkdf2Iterations = 120000;
  static const _pbkdf2SaltLengthBytes = 16;
  static const _pbkdf2DerivedKeyLengthBytes = 32;
  static const _pbkdf2Version = 2;
  static const _sha256LengthBytes = 32;
  static const _secureRandomByteLimit = 256;
  static const _byteMask = 0xff;
  static const _int32Byte3Shift = 24;
  static const _int32Byte2Shift = 16;
  static const _int32Byte1Shift = 8;

  final List<int> Function(int lengthBytes)? _saltGenerator;

  /// Gera uma credencial PBKDF2 nova usando a senha exatamente como digitada.
  ///
  /// Nao aplica trim para preservar a senha escolhida em novos cadastros.
  PasswordHashResult hashNewPassword(String password) {
    final senhaSalt = _gerarSaltBase64();
    final senhaHash = _derivarPbkdf2Base64(
      password,
      senhaSalt,
      iterations: _pbkdf2Iterations,
      derivedKeyLengthBytes: _pbkdf2DerivedKeyLengthBytes,
    );

    return PasswordHashResult(
      senhaHash: senhaHash,
      senhaSalt: senhaSalt,
      senhaAlgoritmo: _pbkdf2Algorithm,
      senhaIteracoes: _pbkdf2Iterations,
      senhaVersao: _pbkdf2Version,
    );
  }

  /// Verifica uma senha contra PBKDF2 atual, SHA-256 legado ou provedor externo.
  ///
  /// PBKDF2 usa a senha sem trim. SHA-256 legado usa trim porque esse era o
  /// comportamento historico antes da migracao.
  bool verifyPassword({required String password, required Usuario usuario}) {
    if (isExternalProvider(usuario)) {
      return false;
    }

    if (usuario.senhaAlgoritmo == _pbkdf2Algorithm) {
      final salt = usuario.senhaSalt;
      if (salt == null || salt.isEmpty || usuario.senhaIteracoes <= 0) {
        return false;
      }

      try {
        final senhaHash = _derivarPbkdf2Base64(
          password,
          salt,
          iterations: usuario.senhaIteracoes,
          derivedKeyLengthBytes: _pbkdf2DerivedKeyLengthBytes,
        );
        return _compararTempoConstante(senhaHash, usuario.senhaHash);
      } on FormatException {
        return false;
      }
    }

    if (usuario.senhaAlgoritmo == _legacySha256Algorithm) {
      return _compararTempoConstante(
        generateLegacySha256Hash(password),
        usuario.senhaHash,
      );
    }

    return false;
  }

  /// Indica se a credencial deve ser migrada para o algoritmo atual.
  bool shouldRehash(Usuario usuario) {
    return usuario.senhaAlgoritmo == _legacySha256Algorithm;
  }

  /// Gera PBKDF2 para um login legado bem-sucedido usando password.trim().
  ///
  /// O trim preserva a semantica do SHA-256 legado, que tratava a senha
  /// trimada como o valor real armazenado.
  PasswordHashResult rehashLegacyPasswordAfterSuccessfulLogin(String password) {
    return hashNewPassword(password.trim());
  }

  /// Gera o SHA-256 legado usado apenas para compatibilidade e testes antigos.
  ///
  /// Este metodo nao deve ser usado em novos cadastros.
  String generateLegacySha256Hash(String password) {
    final bytes = utf8.encode(password.trim());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Indica que a conta autentica por provedor externo, sem senha local.
  bool isExternalProvider(Usuario usuario) {
    return usuario.senhaAlgoritmo == _externalProviderAlgorithm;
  }

  /// Retorna a credencial marcador usada para usuarios sem senha local.
  PasswordHashResult externalProviderCredential() {
    return const PasswordHashResult(
      senhaHash: _externalProviderPasswordHash,
      senhaSalt: null,
      senhaAlgoritmo: _externalProviderAlgorithm,
      senhaIteracoes: 0,
      senhaVersao: _pbkdf2Version,
    );
  }

  String _gerarSaltBase64() {
    final generator = _saltGenerator;
    final bytes = generator == null
        ? _gerarSaltSeguro(_pbkdf2SaltLengthBytes)
        : generator(_pbkdf2SaltLengthBytes);
    return base64Encode(bytes);
  }

  List<int> _gerarSaltSeguro(int lengthBytes) {
    final random = Random.secure();
    return List<int>.generate(
      lengthBytes,
      (_) => random.nextInt(_secureRandomByteLimit),
    );
  }

  String _derivarPbkdf2Base64(
    String password,
    String saltBase64, {
    required int iterations,
    required int derivedKeyLengthBytes,
  }) {
    final passwordBytes = utf8.encode(password);
    final saltBytes = base64Decode(saltBase64);
    final blockCount =
        (derivedKeyLengthBytes + _sha256LengthBytes - 1) ~/ _sha256LengthBytes;
    final derivedKey = <int>[];

    for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
      final block = _pbkdf2Block(
        passwordBytes: passwordBytes,
        saltBytes: saltBytes,
        iterations: iterations,
        blockIndex: blockIndex,
      );
      derivedKey.addAll(block);
    }

    return base64Encode(derivedKey.take(derivedKeyLengthBytes).toList());
  }

  List<int> _pbkdf2Block({
    required List<int> passwordBytes,
    required List<int> saltBytes,
    required int iterations,
    required int blockIndex,
  }) {
    final hmac = Hmac(sha256, passwordBytes);
    var current = hmac.convert([
      ...saltBytes,
      ..._int32BigEndian(blockIndex),
    ]).bytes;
    final output = List<int>.from(current);

    for (var iteration = 2; iteration <= iterations; iteration++) {
      current = hmac.convert(current).bytes;
      for (var index = 0; index < output.length; index++) {
        output[index] ^= current[index];
      }
    }

    return output;
  }

  List<int> _int32BigEndian(int value) {
    return [
      (value >> _int32Byte3Shift) & _byteMask,
      (value >> _int32Byte2Shift) & _byteMask,
      (value >> _int32Byte1Shift) & _byteMask,
      value & _byteMask,
    ];
  }

  bool _compararTempoConstante(String a, String b) {
    if (a.length != b.length) {
      return false;
    }

    var diferenca = 0;
    for (var index = 0; index < a.length; index++) {
      diferenca |= a.codeUnitAt(index) ^ b.codeUnitAt(index);
    }

    return diferenca == 0;
  }
}

/// Representa os campos persistidos de credencial local do usuario.
class PasswordHashResult {
  const PasswordHashResult({
    required this.senhaHash,
    required this.senhaSalt,
    required this.senhaAlgoritmo,
    required this.senhaIteracoes,
    required this.senhaVersao,
  });

  final String senhaHash;
  final String? senhaSalt;
  final String senhaAlgoritmo;
  final int senhaIteracoes;
  final int senhaVersao;
}
