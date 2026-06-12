import 'dart:async';

import '../services/command_service.dart';

typedef VoiceConfirmationCallback = FutureOr<void> Function();

class VoiceConfirmationRequest {
  const VoiceConfirmationRequest({
    required this.id,
    required this.description,
    required this.onConfirm,
    this.onCancel,
  });

  final String id;
  final String description;
  final VoiceConfirmationCallback onConfirm;
  final VoiceConfirmationCallback? onCancel;
}

enum VoiceConfirmationAction { confirmed, cancelled, blocked, notHandled }

class VoiceConfirmationResult {
  const VoiceConfirmationResult({required this.action, required this.message});

  final VoiceConfirmationAction action;
  final String message;

  bool get handled => action != VoiceConfirmationAction.notHandled;
}

class VoiceConfirmationController {
  VoiceConfirmationRequest? _pending;

  bool get hasPendingConfirmation => _pending != null;

  VoiceConfirmationRequest? get pendingConfirmation => _pending;

  void register(VoiceConfirmationRequest request) {
    _pending = request;
  }

  void clear() {
    _pending = null;
  }

  Future<VoiceConfirmationResult> handle(CommandResult command) async {
    final pending = _pending;
    if (pending == null) {
      return const VoiceConfirmationResult(
        action: VoiceConfirmationAction.notHandled,
        message: '',
      );
    }

    switch (command.type) {
      case VoiceCommandType.confirmarAcao:
        _pending = null;
        await pending.onConfirm();
        return VoiceConfirmationResult(
          action: VoiceConfirmationAction.confirmed,
          message: '${pending.description} confirmada.',
        );
      case VoiceCommandType.cancelarAcao:
      case VoiceCommandType.voltar:
        _pending = null;
        await pending.onCancel?.call();
        return VoiceConfirmationResult(
          action: VoiceConfirmationAction.cancelled,
          message: '${pending.description} cancelada.',
        );
      case VoiceCommandType.iniciarGravacao:
      case VoiceCommandType.pausarGravacao:
      case VoiceCommandType.retomarGravacao:
      case VoiceCommandType.encerrarGravacao:
      case VoiceCommandType.pararReproducao:
      case VoiceCommandType.reproduzirGravacao:
      case VoiceCommandType.listarGravacoes:
      case VoiceCommandType.buscarGravacoes:
      case VoiceCommandType.buscarProjetos:
      case VoiceCommandType.limparBusca:
      case VoiceCommandType.scrollBaixo:
      case VoiceCommandType.scrollCima:
      case VoiceCommandType.scrollTopo:
      case VoiceCommandType.scrollFim:
      case VoiceCommandType.criarMarcador:
      case VoiceCommandType.limparTexto:
      case VoiceCommandType.definirNomeProjeto:
      case VoiceCommandType.definirDescricaoProjeto:
      case VoiceCommandType.substituirNomeProjeto:
      case VoiceCommandType.substituirDescricaoProjeto:
      case VoiceCommandType.renomearProjeto:
      case VoiceCommandType.excluirProjeto:
      case VoiceCommandType.abrirProjetoPorNome:
      case VoiceCommandType.abrirNovoProjeto:
      case VoiceCommandType.criarProjeto:
      case VoiceCommandType.cancelarProjeto:
      case VoiceCommandType.abrirDashboard:
      case VoiceCommandType.abrirProjetos:
      case VoiceCommandType.abrirGravacoes:
      case VoiceCommandType.abrirDetalhesGravacao:
      case VoiceCommandType.abrirConfiguracoes:
      case VoiceCommandType.abrirAssistente:
      case VoiceCommandType.abrirHistorico:
      case VoiceCommandType.abrirEditor:
      case VoiceCommandType.renomearGravacao:
      case VoiceCommandType.excluirGravacao:
      case VoiceCommandType.ativarControleVoz:
      case VoiceCommandType.desativarControleVoz:
      case VoiceCommandType.ativarEscutaContinua:
      case VoiceCommandType.desativarEscutaContinua:
      case VoiceCommandType.ativarFeedbackSonoro:
      case VoiceCommandType.desativarFeedbackSonoro:
      case VoiceCommandType.ativarTemaEscuro:
      case VoiceCommandType.desativarTemaEscuro:
      case VoiceCommandType.ativarParadaSilencio:
      case VoiceCommandType.desativarParadaSilencio:
      case VoiceCommandType.definirTempoSilencio:
      case VoiceCommandType.sair:
      case VoiceCommandType.desconhecido:
        return VoiceConfirmationResult(
          action: VoiceConfirmationAction.blocked,
          message: 'Confirme ou cancele a acao pendente antes de continuar.',
        );
    }
  }
}
