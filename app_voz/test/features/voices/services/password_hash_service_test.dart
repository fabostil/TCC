import 'dart:convert';

import 'package:app_voz/features/voices/services/password_hash_service.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pbkdf2Algorithm = 'pbkdf2_sha256';
  const legacyAlgorithm = 'sha256_legacy';
  const externalProviderAlgorithm = 'external_provider';
  const pbkdf2Iterations = 120000;
  const pbkdf2Version = 2;
  const saltLengthBytes = 16;
  const legacyPasswordHash =
      '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8';

  PasswordHashService deterministicService() {
    return PasswordHashService(
      saltGenerator: (lengthBytes) =>
          List<int>.generate(lengthBytes, (index) => index),
    );
  }

  Usuario usuarioComCredencial({
    required PasswordHashResult credential,
    String email = 'alex@example.com',
  }) {
    return Usuario(
      id: 1,
      nome: 'Alex',
      email: email,
      senhaHash: credential.senhaHash,
      senhaSalt: credential.senhaSalt,
      senhaAlgoritmo: credential.senhaAlgoritmo,
      senhaIteracoes: credential.senhaIteracoes,
      senhaVersao: credential.senhaVersao,
    );
  }

  group('PasswordHashService', () {
    test('hashNewPassword retorna credencial PBKDF2 completa', () {
      final credential = deterministicService().hashNewPassword('abc12345');

      expect(credential.senhaAlgoritmo, pbkdf2Algorithm);
      expect(credential.senhaSalt, isNotNull);
      expect(base64Decode(credential.senhaSalt!), hasLength(saltLengthBytes));
      expect(credential.senhaIteracoes, pbkdf2Iterations);
      expect(credential.senhaVersao, pbkdf2Version);
    });

    test('hashNewPassword com saltGenerator fixo e deterministico', () {
      final service = deterministicService();

      final first = service.hashNewPassword('abc12345');
      final second = service.hashNewPassword('abc12345');

      expect(first.senhaSalt, second.senhaSalt);
      expect(first.senhaHash, second.senhaHash);
    });

    test('verifyPassword aceita senha correta para usuario PBKDF2', () {
      final service = deterministicService();
      final usuario = usuarioComCredencial(
        credential: service.hashNewPassword('abc12345'),
      );

      expect(
        service.verifyPassword(password: 'abc12345', usuario: usuario),
        isTrue,
      );
    });

    test('verifyPassword rejeita senha errada para usuario PBKDF2', () {
      final service = deterministicService();
      final usuario = usuarioComCredencial(
        credential: service.hashNewPassword('abc12345'),
      );

      expect(
        service.verifyPassword(password: 'senha-errada', usuario: usuario),
        isFalse,
      );
    });

    test(
      'verifyPassword aceita senha correta para sha256_legacy usando trim',
      () {
        final service = deterministicService();
        final usuario = Usuario(
          id: 1,
          nome: 'Alex',
          email: 'alex@example.com',
          senhaHash: service.generateLegacySha256Hash('abc12345'),
          senhaAlgoritmo: legacyAlgorithm,
        );

        expect(
          service.verifyPassword(password: ' abc12345 ', usuario: usuario),
          isTrue,
        );
      },
    );

    test('verifyPassword rejeita senha errada para sha256_legacy', () {
      final service = deterministicService();
      final usuario = Usuario(
        id: 1,
        nome: 'Alex',
        email: 'alex@example.com',
        senhaHash: service.generateLegacySha256Hash('abc12345'),
        senhaAlgoritmo: legacyAlgorithm,
      );

      expect(
        service.verifyPassword(password: 'senha-errada', usuario: usuario),
        isFalse,
      );
    });

    test('shouldRehash retorna true somente para sha256_legacy', () {
      final service = deterministicService();
      final legacy = Usuario(
        nome: 'Alex',
        email: 'legacy@example.com',
        senhaHash: 'hash',
        senhaAlgoritmo: legacyAlgorithm,
      );
      final pbkdf2 = usuarioComCredencial(
        credential: service.hashNewPassword('abc12345'),
        email: 'pbkdf2@example.com',
      );
      final external = usuarioComCredencial(
        credential: service.externalProviderCredential(),
        email: 'external@example.com',
      );

      expect(service.shouldRehash(legacy), isTrue);
      expect(service.shouldRehash(pbkdf2), isFalse);
      expect(service.shouldRehash(external), isFalse);
    });

    test('rehashLegacyPasswordAfterSuccessfulLogin usa password.trim()', () {
      final service = deterministicService();
      final credential = service.rehashLegacyPasswordAfterSuccessfulLogin(
        ' abc12345 ',
      );
      final usuario = usuarioComCredencial(credential: credential);

      expect(
        service.verifyPassword(password: 'abc12345', usuario: usuario),
        isTrue,
      );
      expect(
        service.verifyPassword(password: ' abc12345 ', usuario: usuario),
        isFalse,
      );
    });

    test('generateLegacySha256Hash preserva hash legado com trim', () {
      final service = deterministicService();

      expect(
        service.generateLegacySha256Hash(' password '),
        legacyPasswordHash,
      );
    });

    test(
      'isExternalProvider identifica somente algoritmo external_provider',
      () {
        final service = deterministicService();
        final external = usuarioComCredencial(
          credential: service.externalProviderCredential(),
          email: 'external@example.com',
        );
        final pbkdf2 = usuarioComCredencial(
          credential: service.hashNewPassword('abc12345'),
          email: 'pbkdf2@example.com',
        );

        expect(service.isExternalProvider(external), isTrue);
        expect(service.isExternalProvider(pbkdf2), isFalse);
      },
    );

    test('external_provider nao autentica por senha local', () {
      final service = deterministicService();
      final usuario = Usuario(
        id: 1,
        nome: 'Alex',
        email: 'alex@example.com',
        senhaHash: 'external_provider',
        senhaAlgoritmo: externalProviderAlgorithm,
        senhaVersao: pbkdf2Version,
      );

      expect(
        service.verifyPassword(password: 'qualquer-senha', usuario: usuario),
        isFalse,
      );
    });
  });
}
