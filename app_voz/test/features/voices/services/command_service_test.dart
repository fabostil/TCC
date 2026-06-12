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
      expect(
        service.normalize('  Abrir,   Hist\u00f3rico!  '),
        'abrir historico',
      );
    });

    test('normalizacao permite matching com caixa alta e pontuacao', () {
      expect(
        service.interpret('Configura\u00e7\u00f5es!!!').type,
        VoiceCommandType.abrirConfiguracoes,
      );
      expect(
        service.interpret('  Abrir   Hist\u00f3rico  ').type,
        VoiceCommandType.abrirHistorico,
      );
      expect(
        service.interpret('INICIAR GRAVA\u00c7\u00c3O').type,
        VoiceCommandType.iniciarGravacao,
      );
      expect(
        service.interpret('come\u00e7ar a gravar').type,
        VoiceCommandType.iniciarGravacao,
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
      expect(
        service.interpret('come\u00e7ar grava\u00e7\u00e3o').type,
        VoiceCommandType.iniciarGravacao,
      );
      expect(
        service.interpret('come\u00e7ar a gravar').type,
        VoiceCommandType.iniciarGravacao,
      );
      expect(
        service.interpret('registrar \u00e1udio').type,
        VoiceCommandType.iniciarGravacao,
      );
      expect(service.interpret('pausar').type, VoiceCommandType.pausarGravacao);
      expect(service.interpret('pausa').type, VoiceCommandType.pausarGravacao);
      expect(
        service.interpret('dar pausa').type,
        VoiceCommandType.pausarGravacao,
      );
      expect(
        service.interpret('pausar grava\u00e7\u00e3o').type,
        VoiceCommandType.pausarGravacao,
      );
      expect(
        service.interpret('retomar grava\u00e7\u00e3o').type,
        VoiceCommandType.retomarGravacao,
      );
      expect(
        service.interpret('continuar grava\u00e7\u00e3o').type,
        VoiceCommandType.retomarGravacao,
      );
      expect(
        service.interpret('voltar a gravar').type,
        VoiceCommandType.retomarGravacao,
      );
      expect(
        service.interpret('parar grava\u00e7\u00e3o').type,
        VoiceCommandType.encerrarGravacao,
      );
      expect(
        service.interpret('encerrar grava\u00e7\u00e3o').type,
        VoiceCommandType.encerrarGravacao,
      );
      expect(
        service.interpret('finalizar grava\u00e7\u00e3o').type,
        VoiceCommandType.encerrarGravacao,
      );
      expect(
        service.interpret('salvar grava\u00e7\u00e3o').type,
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
        service.interpret('dar play').type,
        VoiceCommandType.reproduzirGravacao,
      );
      expect(
        service.interpret('ouvir grava\u00e7\u00e3o').type,
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

    test('reconhece comandos de navegacao', () {
      expect(
        service.interpret('dashboard').type,
        VoiceCommandType.abrirDashboard,
      );
      expect(
        service.interpret('abrir dashboard').type,
        VoiceCommandType.abrirDashboard,
      );
      expect(
        service.interpret('ver indicadores').type,
        VoiceCommandType.abrirDashboard,
      );
      expect(
        service.interpret('meu painel').type,
        VoiceCommandType.abrirDashboard,
      );
      expect(
        service.interpret('projetos').type,
        VoiceCommandType.abrirProjetos,
      );
      expect(
        service.interpret('meus projetos').type,
        VoiceCommandType.abrirProjetos,
      );
      expect(
        service.interpret('vai para projetos').type,
        VoiceCommandType.abrirProjetos,
      );
      expect(
        service.interpret('gravacoes').type,
        VoiceCommandType.abrirGravacoes,
      );
      expect(
        service.interpret('minhas grava\u00e7\u00f5es').type,
        VoiceCommandType.abrirGravacoes,
      );
      expect(
        service.interpret('abre grava\u00e7\u00f5es').type,
        VoiceCommandType.abrirGravacoes,
      );
      expect(
        service.interpret('configura\u00e7\u00f5es').type,
        VoiceCommandType.abrirConfiguracoes,
      );
      expect(
        service.interpret('abrir configura\u00e7\u00f5es').type,
        VoiceCommandType.abrirConfiguracoes,
      );
      expect(
        service.interpret('prefer\u00eancias').type,
        VoiceCommandType.abrirConfiguracoes,
      );
      expect(
        service.interpret('hist\u00f3rico').type,
        VoiceCommandType.abrirHistorico,
      );
      expect(
        service.interpret('abrir hist\u00f3rico').type,
        VoiceCommandType.abrirHistorico,
      );
      expect(
        service.interpret('novo projeto').type,
        VoiceCommandType.abrirNovoProjeto,
      );
      expect(
        service.interpret('adicionar projeto').type,
        VoiceCommandType.abrirNovoProjeto,
      );
      expect(
        service.interpret('nova m\u00fasica').type,
        VoiceCommandType.abrirNovoProjeto,
      );
      expect(
        service.interpret('criar projeto').type,
        VoiceCommandType.criarProjeto,
      );
      expect(
        service.interpret('abrir editor').type,
        VoiceCommandType.abrirEditor,
      );
      expect(service.interpret('voltar').type, VoiceCommandType.voltar);
      expect(service.interpret('volta').type, VoiceCommandType.voltar);
      expect(
        service.interpret('voltar para tela inicial').type,
        VoiceCommandType.voltar,
      );
      expect(
        service.interpret('ir para o in\u00edcio').type,
        VoiceCommandType.voltar,
      );
      expect(service.interpret('in\u00edcio').type, VoiceCommandType.voltar);
      expect(service.interpret('sair').type, VoiceCommandType.sair);
    });

    test('reconhece comandos contextuais com parametros', () {
      final nomeProjeto = service.interpret('nome do projeto beat novo');
      expect(nomeProjeto.type, VoiceCommandType.definirNomeProjeto);
      expect(nomeProjeto.parametro, 'beat novo');

      final nomeNatural = service.interpret(
        'eu quero que voce coloque o nome abacate',
      );
      expect(nomeNatural.type, VoiceCommandType.definirNomeProjeto);
      expect(nomeNatural.parametro, 'abacate');

      final descricao = service.interpret(
        'descricao do projeto ideia simples para tocar na rua',
      );
      expect(descricao.type, VoiceCommandType.definirDescricaoProjeto);
      expect(descricao.parametro, 'Ideia simples para tocar na rua.');

      final substituirNome = service.interpret(
        'apague o nome abacate e coloque alface',
      );
      expect(substituirNome.type, VoiceCommandType.substituirNomeProjeto);
      expect(substituirNome.parametro, 'alface');

      final substituirDescricao = service.interpret(
        'apague a descricao e coloque minha alface e muito boa',
      );
      expect(
        substituirDescricao.type,
        VoiceCommandType.substituirDescricaoProjeto,
      );
      expect(substituirDescricao.parametro, 'Minha alface e muito boa.');

      final abrirProjeto = service.interpret('abrir projeto demo acustica');
      expect(abrirProjeto.type, VoiceCommandType.abrirProjetoPorNome);
      expect(abrirProjeto.parametro, 'demo acustica');

      final abrirProjetoSemNome = service.interpret('abrir projeto');
      expect(abrirProjetoSemNome.type, VoiceCommandType.abrirProjetoPorNome);
      expect(abrirProjetoSemNome.parametro, isNull);

      final renomearProjeto = service.interpret(
        'renomear projeto tomate para alface',
      );
      expect(renomearProjeto.type, VoiceCommandType.renomearProjeto);
      expect(renomearProjeto.parametro, 'tomate');
      expect(renomearProjeto.parametroSecundario, 'alface');

      final excluirProjeto = service.interpret('excluir projeto demo acustica');
      expect(excluirProjeto.type, VoiceCommandType.excluirProjeto);
      expect(excluirProjeto.parametro, 'demo acustica');

      final excluirProjetoSemNome = service.interpret('apagar projeto');
      expect(excluirProjetoSemNome.type, VoiceCommandType.excluirProjeto);
      expect(excluirProjetoSemNome.parametro, isNull);

      final renomearProjetoSemNome = service.interpret('renomear projeto');
      expect(renomearProjetoSemNome.type, VoiceCommandType.renomearProjeto);
      expect(renomearProjetoSemNome.parametro, isNull);

      final reproduzir = service.interpret('reproduzir gravacao ideia um');
      expect(reproduzir.type, VoiceCommandType.reproduzirGravacao);
      expect(reproduzir.parametro, 'ideia um');

      final detalhes = service.interpret('abrir detalhes da gravacao ideia um');
      expect(detalhes.type, VoiceCommandType.abrirDetalhesGravacao);
      expect(detalhes.parametro, 'ideia um');

      final detalhesSemNome = service.interpret('ver detalhes');
      expect(detalhesSemNome.type, VoiceCommandType.abrirDetalhesGravacao);
      expect(detalhesSemNome.parametro, isNull);

      final excluirGravacao = service.interpret('apagar gravacao');
      expect(excluirGravacao.type, VoiceCommandType.excluirGravacao);
      expect(excluirGravacao.parametro, isNull);

      final renomear = service.interpret(
        'renomear gravacao ideia um para refrao final',
      );
      expect(renomear.type, VoiceCommandType.renomearGravacao);
      expect(renomear.parametro, 'ideia um');
      expect(renomear.parametroSecundario, 'refrao final');

      final tempo = service.interpret('tempo de silencio 9 segundos');
      expect(tempo.type, VoiceCommandType.definirTempoSilencio);
      expect(tempo.parametro, '9');

      final buscarProjeto = service.interpret('buscar projeto demo');
      expect(buscarProjeto.type, VoiceCommandType.buscarProjetos);
      expect(buscarProjeto.parametro, 'demo');

      final buscarGravacao = service.interpret('filtrar gravacoes refrao');
      expect(buscarGravacao.type, VoiceCommandType.buscarGravacoes);
      expect(buscarGravacao.parametro, 'refrao');

      expect(
        service.interpret('limpar busca').type,
        VoiceCommandType.limparBusca,
      );
    });

    test('reconhece frases naturais frequentes sem acionar IA', () {
      expect(
        service.interpret('quero ver minha atividade recente').type,
        VoiceCommandType.abrirHistorico,
      );
      expect(
        service.interpret('me mostra meus numeros').type,
        VoiceCommandType.abrirDashboard,
      );
    });

    test('respeita comandos negativos antes dos positivos', () {
      expect(
        service.interpret('desativar escuta continua').type,
        VoiceCommandType.desativarEscutaContinua,
      );
      expect(
        service.interpret('desativar feedback sonoro').type,
        VoiceCommandType.desativarFeedbackSonoro,
      );
      expect(
        service.interpret('desativar comandos de voz').type,
        VoiceCommandType.desativarControleVoz,
      );
      expect(
        service.interpret('desativar parada por silencio').type,
        VoiceCommandType.desativarParadaSilencio,
      );
      expect(
        service.interpret('ativar tema escuro').type,
        VoiceCommandType.ativarTemaEscuro,
      );
      expect(
        service.interpret('modo escuro').type,
        VoiceCommandType.ativarTemaEscuro,
      );
      expect(
        service.interpret('ativar tema claro').type,
        VoiceCommandType.desativarTemaEscuro,
      );
      expect(
        service.interpret('tema claro').type,
        VoiceCommandType.desativarTemaEscuro,
      );
      expect(
        service.interpret('ligar controle por voz').type,
        VoiceCommandType.ativarControleVoz,
      );
      expect(
        service.interpret('desligar escuta cont\u00ednua').type,
        VoiceCommandType.desativarEscutaContinua,
      );
      expect(
        service.interpret('ativar feedback sonoro').type,
        VoiceCommandType.ativarFeedbackSonoro,
      );
      expect(service.interpret('sim').type, VoiceCommandType.confirmarAcao);
      expect(service.interpret('desistir').type, VoiceCommandType.cancelarAcao);
    });

    test('mantem comandos destrutivos ambiguos sem acao direta', () {
      final apagar = service.interpret('apagar');

      expect(apagar.type, VoiceCommandType.desconhecido);
      expect(apagar.recognized, isFalse);
    });

    test('retorna desconhecido para comando nao mapeado', () {
      final result = service.interpret('abrir afinador');

      expect(result.type, VoiceCommandType.desconhecido);
      expect(result.recognized, isFalse);
      expect(result.statusReconhecimento, 'nao_reconhecido');
    });
  });
}
