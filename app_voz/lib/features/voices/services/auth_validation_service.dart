class AuthValidationService {
  const AuthValidationService();

  static final _emailRegex = RegExp(
    r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
    caseSensitive: false,
  );

  String? validarNome(String? value) {
    final nome = value?.trim() ?? '';

    if (nome.isEmpty) {
      return 'Informe seu nome.';
    }

    if (nome.length < 3) {
      return 'O nome deve ter pelo menos 3 caracteres.';
    }

    return null;
  }

  String? validarEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Informe seu e-mail.';
    }

    if (!_emailRegex.hasMatch(email) ||
        email.contains('..') ||
        email.startsWith('.') ||
        email.endsWith('.')) {
      return 'Informe um e-mail válido.';
    }

    final dominio = email.split('@').last;
    final partesDominio = dominio.split('.');
    if (partesDominio.any((parte) => parte.isEmpty || parte.startsWith('-'))) {
      return 'Informe um e-mail válido.';
    }

    return null;
  }

  String? validarSenhaLogin(String? value) {
    if (value == null || value.isEmpty) {
      return 'Informe sua senha.';
    }

    return null;
  }

  String? validarSenhaCadastro(String? value) {
    final senha = value ?? '';

    if (senha.isEmpty) {
      return 'Informe uma senha.';
    }

    if (senha.length < 8) {
      return 'A senha deve ter pelo menos 8 caracteres.';
    }

    final temLetra = RegExp('[A-Za-z]').hasMatch(senha);
    final temNumero = RegExp(r'\d').hasMatch(senha);

    if (!temLetra || !temNumero) {
      return 'Use letras e números na senha.';
    }

    return null;
  }

  String? validarConfirmacaoSenha(String? value, String senha) {
    if (value == null || value.isEmpty) {
      return 'Confirme sua senha.';
    }

    if (value != senha) {
      return 'As senhas não conferem.';
    }

    return null;
  }
}
