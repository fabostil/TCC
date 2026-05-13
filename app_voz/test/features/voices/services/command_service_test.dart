import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = CommandService();

  group('CommandService', () {
    test('normaliza texto removendo acentos e espacos duplicados', () {
      expect(
        service.normalize('  Iniciar   Grava\u00e7\u00e3o  '),
        'iniciar gravacao',
      );
    });

    test('reconhece comandos de gravacao', () {
      expect(
        service.interpret('iniciar grava\u00e7\u00e3o').type,
        VoiceCommandType.iniciarGravacao,
      );
      expect(
        service.interpret('gravar').type,
        VoiceCommandType.iniciarGravacao,
      );
      expect(service.interpret('pausar').type, VoiceCommandType.pausarGravacao);
      expect(
        service.interpret('retomar grava\u00e7\u00e3o').type,
        VoiceCommandType.retomarGravacao,
      );
      expect(
        service.interpret('finalizar grava\u00e7\u00e3o').type,
        VoiceCommandType.encerrarGravacao,
      );
    });

    test('reconhece comandos de reproducao, lista e marcador', () {
      expect(
        service.interpret('parar reprodu\u00e7\u00e3o').type,
        VoiceCommandType.pararReproducao,
      );
      expect(
        service.interpret('tocar').type,
        VoiceCommandType.reproduzirGravacao,
      );
      expect(
        service.interpret('mostrar grava\u00e7\u00f5es').type,
        VoiceCommandType.listarGravacoes,
      );
      expect(
        service.interpret('criar marcador').type,
        VoiceCommandType.criarMarcador,
      );
    });

    test('retorna desconhecido para comando nao mapeado', () {
      final result = service.interpret('abrir afinador');

      expect(result.type, VoiceCommandType.desconhecido);
      expect(result.recognized, isFalse);
      expect(result.statusReconhecimento, 'nao_reconhecido');
    });
  });
}
