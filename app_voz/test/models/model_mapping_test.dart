import 'package:app_voz/models/comando_personalizado.dart';
import 'package:app_voz/models/comando_voz.dart';
import 'package:app_voz/models/configuracao_app.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:app_voz/models/historico_acao.dart';
import 'package:app_voz/models/projeto.dart';
import 'package:app_voz/models/usuario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('model mapping', () {
    test('Usuario round-trip preserva campos principais', () {
      final usuario = Usuario(
        id: 1,
        nome: 'Alex',
        email: 'alex@example.com',
        senhaHash: 'hash',
      );

      final map = usuario.toMap();
      final parsed = Usuario.fromMap(map);

      expect(parsed.id, 1);
      expect(parsed.nome, 'Alex');
      expect(parsed.email, 'alex@example.com');
      expect(parsed.senhaHash, 'hash');
    });

    test('Projeto round-trip preserva descricao opcional', () {
      final projeto = Projeto(
        id: 2,
        usuarioId: 1,
        nome: 'Demo',
        descricao: 'Ideia inicial',
        dataCriacao: '2026-05-18T10:00:00.000',
      );

      final parsed = Projeto.fromMap(projeto.toMap());

      expect(parsed.id, 2);
      expect(parsed.usuarioId, 1);
      expect(parsed.nome, 'Demo');
      expect(parsed.descricao, 'Ideia inicial');
      expect(parsed.dataCriacao, '2026-05-18T10:00:00.000');
    });

    test('Gravacao usa duracao zero quando coluna antiga nao existe', () {
      final parsed = Gravacao.fromMap({
        'id': 3,
        'usuario_id': 1,
        'projeto_id': 2,
        'nome': 'Refrao',
        'caminho_arquivo': '/tmp/refrao.m4a',
        'data_criacao': '2026-05-18T10:00:00.000',
      });

      expect(parsed.id, 3);
      expect(parsed.projetoId, 2);
      expect(parsed.duracaoSegundos, 0);
      expect(parsed.toMap()['duracao_segundos'], 0);
    });

    test('ComandoVoz round-trip preserva status e acao opcional', () {
      final comando = ComandoVoz(
        id: 4,
        usuarioId: 1,
        textoReconhecido: 'abrir dashboard',
        tipoComando: 'abrir_dashboard',
        statusReconhecimento: 'reconhecido',
        acaoExecutada: 'Abrir dashboard',
        dataHora: '2026-05-18T10:00:00.000',
      );

      final parsed = ComandoVoz.fromMap(comando.toMap());

      expect(parsed.tipoComando, 'abrir_dashboard');
      expect(parsed.statusReconhecimento, 'reconhecido');
      expect(parsed.acaoExecutada, 'Abrir dashboard');
    });

    test('HistoricoAcao round-trip preserva vinculos opcionais', () {
      final historico = HistoricoAcao(
        id: 5,
        usuarioId: 1,
        gravacaoId: 3,
        projetoId: 2,
        tipo: 'gravacao_reproduzida',
        descricao: 'Reproduziu gravacao',
        dataHora: '2026-05-18T10:00:00.000',
      );

      final parsed = HistoricoAcao.fromMap(historico.toMap());

      expect(parsed.gravacaoId, 3);
      expect(parsed.projetoId, 2);
      expect(parsed.tipo, 'gravacao_reproduzida');
    });

    test('ConfiguracaoApp converte booleanos para inteiros SQLite', () {
      final configuracao = ConfiguracaoApp(
        comandosVozAtivos: true,
        primeiraExecucaoConcluida: false,
        escutaContinua: true,
        feedbackSonoro: false,
        paradaSilencio: true,
        tempoSilencioSegundos: 6,
        temaEscuro: true,
        dataAtualizacao: '2026-05-18T10:00:00.000',
      );

      final map = configuracao.toMap();
      final parsed = ConfiguracaoApp.fromMap(map);

      expect(map['comandos_voz_ativos'], 1);
      expect(map['primeira_execucao_concluida'], 0);
      expect(parsed.escutaContinua, isTrue);
      expect(parsed.temaEscuro, isTrue);
      expect(parsed.tempoSilencioSegundos, 6);
    });

    test('ConfiguracaoApp fromMap tolera banco antigo sem tema_escuro', () {
      final parsed = ConfiguracaoApp.fromMap({
        'id': 1,
        'comandos_voz_ativos': 1,
        'primeira_execucao_concluida': 1,
        'escuta_continua': 1,
        'feedback_sonoro': 0,
        'parada_silencio': 1,
        'tempo_silencio_segundos': 6,
        'data_atualizacao': '2026-05-18T10:00:00.000',
      });

      expect(parsed.temaEscuro, isFalse);
    });

    test('ComandoPersonalizado copyWith preserva campos nao alterados', () {
      final comando = ComandoPersonalizado(
        id: 6,
        usuarioId: 1,
        frase: 'abrir estudio',
        tipoComando: 'abrir_editor',
        ativo: true,
        dataCriacao: '2026-05-18T10:00:00.000',
      );

      final alterado = comando.copyWith(ativo: false);
      final parsed = ComandoPersonalizado.fromMap(alterado.toMap());

      expect(parsed.id, 6);
      expect(parsed.frase, 'abrir estudio');
      expect(parsed.tipoComando, 'abrir_editor');
      expect(parsed.ativo, isFalse);
    });
  });
}
