# Voice-First Architecture Foundation

## Objetivo

Esta etapa inicia a arquitetura experimental para transformar o app em um
sistema hands-free real, com uma sessao central de voz e audio. Nao inclui
wake word. O foco e previsibilidade, recovery e eliminacao gradual de controle
distribuido de microfone.

## Gargalos Atuais

- `ContextualVoiceListeningMixin` ainda controla estado local com booleans
  (`voiceOuvindo`, `voiceIaPensando`, `voiceExecutandoComando`).
- `EditorPage` ainda possui fluxo proprio por causa do modo hibrido entre STT
  e gravacao real.
- `SpeechService`, `record` e `just_audio` podem ser acionados por caminhos
  diferentes.
- Recovery de escuta existe, mas historicamente ficava acoplado aos owners e
  nao tinha log estruturado.
- Diagnostico de conflitos de microfone dependia de `debugPrint` pontual ou de
  inferencia manual.

## Fundacao Criada

### VoiceStateMachine

Estado canonico:

- `idle`
- `listening`
- `processing`
- `executing`
- `recording`
- `paused`
- `recovering`
- `error`
- `disabled`

A state machine registra transicoes, owner, motivo, mensagem, timestamp e
tentativas de recovery.

### VoiceSessionManager

Responsavel por:

- ownership de STT;
- reserva de microfone por gravacao;
- marcacao de playback;
- cancelamento em navegacao;
- recovery centralizado;
- limite de tentativas para evitar loops;
- motivo da ultima falha;
- exposicao de diagnosticos.

### VoiceDiagnostics

Eventos registrados:

- transicao de estado;
- conflito de microfone;
- inicio/parada de escuta;
- inicio/parada de gravacao;
- inicio/parada de playback;
- recovery agendado/tentado/ignorado;
- erro.

## Compatibilidade

`VoiceListeningCoordinator` virou fachada de compatibilidade e delega para
`VoiceSessionManager`. Isso preserva as telas atuais enquanto permite migracao
gradual.

`ContextualVoiceListeningMixin` e `EditorPage` continuam operando como antes,
mas agora publicam seus estados na state machine central.

## Consolidacao Operacional

Nesta etapa de consolidacao, o ciclo real de STT passou a ser iniciado,
interrompido e cancelado pelo `VoiceSessionManager`. O mixin contextual e o
Editor deixaram de chamar `SpeechService` diretamente.

`AudioPlayerService` passou a registrar playback na sessao global. Ao iniciar
reproducao, ele pede ownership ao manager; se STT estiver ativo, o manager
cancela a escuta antes do playback. Se uma gravacao estiver ativa, o playback e
bloqueado.

`AudioRecordingService` passou a registrar entrada/saida de modo gravacao no
manager. Pausa e retomada tambem publicam estados na state machine central.

O manager tambem passou a rejeitar stop/cancel vindos de owners antigos quando
outro owner ja assumiu a escuta. Isso protege retomadas atrasadas de rotas
anteriores e reduz risco de multiplas instancias concorrentes derrubarem a
sessao ativa.

## Refatoracao Gradual Recomendada

1. Remover booleans locais redundantes das paginas, mantendo apenas snapshot de
   UI derivado da state machine.
2. Extrair do `EditorPage` um controller/use case dedicado para intencoes de
   gravacao, mantendo a pagina como apresentacao.
3. Criar contratos explicitos para audio focus Android quando houver camada
   nativa.
4. Criar tela/overlay de diagnostico interno para visualizar eventos recentes.
5. Validar em Android real: Home em foreground, troca de rotas, timeout STT,
   gravacao, parada por silencio e retorno da escuta.
6. Somente depois avaliar wake word nativo/offline.
