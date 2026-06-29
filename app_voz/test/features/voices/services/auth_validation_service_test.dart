import 'package:app_voz/features/voices/services/auth_validation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthValidationService', () {
    const service = AuthValidationService();

    test('aceita e-mails estruturalmente validos', () {
      expect(service.validarEmail('musico@example.com'), isNull);
      expect(service.validarEmail('produtor.nome+demo@gmail.com'), isNull);
    });

    test('rejeita e-mails sem estrutura real de dominio', () {
      expect(service.validarEmail('abc'), isNotNull);
      expect(service.validarEmail('abc@teste'), isNotNull);
      expect(service.validarEmail('abc@@teste.com'), isNotNull);
      expect(service.validarEmail('abc@teste..com'), isNotNull);
    });

    test('exige senha de cadastro mais forte que o minimo antigo', () {
      expect(service.validarSenhaCadastro('123456'), isNotNull);
      expect(service.validarSenhaCadastro('abcdefgh'), isNotNull);
      expect(service.validarSenhaCadastro('abc12345'), isNull);
    });
  });
}
