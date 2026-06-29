import 'dart:io';

import 'package:app_voz/features/voices/services/auth_session_service.dart';
import 'package:app_voz/features/voices/services/auth_startup_service.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthStartupService', () {
    test('sem sessao abre fluxo nao autenticado', () async {
      final service = AuthStartupService(
        sessionService: _FakeAuthSessionService(restoredUser: null),
      );

      final result = await service.resolve();

      expect(result.authenticated, isFalse);
      expect(result.usuario, isNull);
    });

    test('com sessao valida abre fluxo autenticado', () async {
      final service = AuthStartupService(
        sessionService: _FakeAuthSessionService(restoredUser: _usuario),
      );

      final result = await service.resolve();

      expect(result.authenticated, isTrue);
      expect(result.usuario, same(_usuario));
    });

    test('sessao para usuario inexistente e limpa e volta ao Login', () async {
      final directory = await Directory.systemTemp.createTemp(
        'auth_startup_invalid_session',
      );
      final sessionService = AuthSessionService(
        sessionDirectoryPathProvider: () async => directory.path,
        userById: (_) async => null,
      );
      await sessionService.saveAuthenticatedUser(_usuario);

      final result = await AuthStartupService(
        sessionService: sessionService,
      ).resolve();

      expect(result.authenticated, isFalse);
      expect(result.usuario, isNull);
      expect(directory.listSync().whereType<File>(), isEmpty);
    });
  });
}

class _FakeAuthSessionService extends AuthSessionService {
  _FakeAuthSessionService({required this.restoredUser})
    : super(
        googleSignOut: () async {},
        stopActiveVoiceSession: () async {},
        clearActiveVoiceContext: () {},
        clearRuntimeVoiceSession: () {},
      );

  final Usuario? restoredUser;

  @override
  Future<Usuario?> restoreAuthenticatedUser() async => restoredUser;
}

final _usuario = Usuario(
  id: 7,
  nome: 'Ana Silva',
  email: 'ana@example.com',
  senhaHash: 'hash',
);
