# Voice-First Realtime Architecture

Data: 2026-05-20
Escopo: arquitetura experimental de voz e audio realtime no workspace atual da branch `feature/app-robusto-voice-first`.
Status: em consolidacao, ainda nao commitado como baseline final.

Este documento descreve o estado tecnico atual da nova arquitetura Voice-First Realtime. Ele deve ser usado como ponto de retomada para futuras sessoes de desenvolvimento, revisao e estabilizacao. O objetivo nao e documentar apenas o comportamento visivel do app, mas a fundacao operacional que esta sendo criada para transformar o produto em um sistema voice-first hands-free, previsivel e tolerante a falhas.

## 1. Objetivo arquitetural

O projeto esta migrando de uma arquitetura de voz distribuida em paginas para um core operacional centralizado. A direcao atual e:

- paginas emitem intencoes e renderizam estado;
- o ciclo real de STT fica sob uma autoridade central;
- gravacao e playback participam da mesma sessao de audio;
- conflitos de microfone sao registrados e bloqueados explicitamente;
- recovery de escuta e retomada automatica deixam de depender de timers soltos em paginas;
- a arquitetura permanece incremental para preservar funcionalidades existentes.

O sistema ainda nao implementa wake word. A decisao atual e estabilizar sessao, ownership, recovery, gravacao e playback antes de abrir uma camada always-on.

## 2. Componentes centrais

### 2.1 `SpeechService`

Arquivo: `lib/features/voices/services/speech_service.dart`

Responsabilidade:

- encapsular `speech_to_text`;
- manter singleton via `SpeechService.instance`;
- solicitar permissao de microfone;
- inicializar locale, preferindo `pt_BR`;
- iniciar janela de escuta com `SpeechListenOptions`;
- debouncer de resultados parciais;
- deduplicacao de textos repetidos em janela curta;
- expor `isListening`;
- parar/cancelar STT.

Decisao importante: `SpeechService` ainda e a integracao tecnica direta com o plugin de STT, mas nao deve ser acionado diretamente por paginas novas. O caminho arquitetural desejado e `pagina/mixin -> VoiceSessionManager -> SpeechService`.

### 2.2 `VoiceStateMachine`

Arquivo: `lib/features/voices/coordination/voice_state_machine.dart`

Estados canonicos:

- `idle`
- `listening`
- `processing`
- `executing`
- `recording`
- `paused`
- `recovering`
- `error`
- `disabled`

Responsabilidade:

- manter `VoiceStateSnapshot`;
- registrar estado atual, estado anterior, owner, mensagem, motivo, timestamp e tentativas de recovery;
- validar transicoes basicas;
- impedir transicoes invalidas quando nao houver `force`;
- emitir diagnosticos de transicao;
- permitir reset em testes.

Regras atuais relevantes:

- de `disabled`, somente `idle` e permitido sem force;
- de `recording`, sao permitidos `paused`, `idle`, `error` e `disabled`;
- de `recovering`, sao permitidos `listening`, `idle`, `error`, `disabled` e `recording`;
- algumas chamadas ainda usam `force: true` para compatibilidade com paginas existentes.

Trade-off: a state machine ja centraliza estados, mas ainda convive com `VoiceSessionState`, que e um estado de apresentacao por tela. Isso e aceitavel na migracao incremental, mas nao deve ser o estado canonico futuro.

### 2.3 `VoiceSessionManager`

Arquivo: `lib/features/voices/coordination/voice_session_manager.dart`

Responsabilidade:

- ser a autoridade central de sessao de voz/audio;
- controlar ownership ativo (`activeOwnerId`);
- controlar tipo de owner de audio (`none`, `stt`, `recorder`, `playback`);
- iniciar/parar/cancelar STT;
- bloquear STT quando gravacao estiver ativa;
- cancelar STT quando playback assume audio;
- bloquear playback durante gravacao;
- entrar e sair do modo gravacao;
- marcar processing/executing/disabled;
- registrar falhas;
- agendar recovery com limite de tentativas;
- invalidar recoveries antigos por geracao;
- expor `VoiceDiagnostics`.

Conceito central: o manager e o cerebro operacional da sessao realtime. Mesmo que algumas paginas ainda tenham estado local para UI, a decisao sobre quem pode usar STT, gravacao ou playback deve passar pelo manager.

Tipos de ownership:

```text
VoiceAudioOwnerType.none      nenhum recurso ativo
VoiceAudioOwnerType.stt       speech-to-text ativo
VoiceAudioOwnerType.recorder  record reservando microfone
VoiceAudioOwnerType.playback  just_audio reproduzindo audio
```

Recovery atual:

- delay normal: 700 ms;
- delay apos erro: 2 s;
- maximo: 3 tentativas;
- cada agendamento captura uma `generation`;
- qualquer mudanca relevante de sessao invalida recoveries antigos;
- o recovery revalida condicoes antes de executar;
- se outro owner assumiu a sessao, o recovery e ignorado.

Risco atual: algumas partes ainda chamam `VoiceListeningCoordinator`, que delega ao manager. Isso e uma fachada de compatibilidade, nao a autoridade real desejada no fim da migracao.

### 2.4 `VoiceDiagnostics`

Arquivo: `lib/features/voices/coordination/voice_diagnostics.dart`

Responsabilidade:

- manter uma lista circular de eventos recentes;
- registrar eventos via `debugPrint`;
- emitir `ChangeNotifier`;
- permitir observabilidade futura em overlay/tela interna.

Eventos atuais:

- `stateTransition`
- `microphoneConflict`
- `listeningStarted`
- `listeningStopped`
- `recordingStarted`
- `recordingStopped`
- `playbackStarted`
- `playbackStopped`
- `recoveryScheduled`
- `recoveryAttempted`
- `recoverySkipped`
- `error`

Lacuna: os eventos ainda nao sao persistidos nem exibidos em uma UI de diagnostico. Eles existem em memoria e log.

### 2.5 `VoiceListeningCoordinator`

Arquivo: `lib/features/voices/coordination/voice_listening_coordinator.dart`

Responsabilidade atual:

- manter compatibilidade com codigo antigo;
- delegar ownership, release, navigation, recording mode e recovery para `VoiceSessionManager`;
- preservar nomes anteriores como `scheduleContinuousRestart`, `releaseAndStop` e `recordingModeActive`.

Decisao: este componente nao deve crescer. Ele deve encolher ate desaparecer ou virar apenas adapter temporario. O manager e a autoridade real.

### 2.6 `VoiceSessionState`

Arquivo: `lib/features/voices/coordination/voice_session_state.dart`

Responsabilidade:

- representar fases de UI/contexto local;
- expor flags como `isListening`, `isThinking`, `isBusy`;
- mapear fases antigas para nomes diagnosticos.

Fases atuais:

- `idle`
- `listening`
- `processingCommand`
- `aiThinking`
- `manualPaused`
- `recordingLocked`
- `error`

Trade-off: `VoiceSessionState` e menor que a `VoiceStateMachine` e ainda esta orientado a UI. Futuramente, deve ser derivado do snapshot canonico da state machine ou substituido por um view-model.

### 2.7 `ContextualVoiceListeningMixin`

Arquivo: `lib/features/voices/coordination/contextual_voice_listening_mixin.dart`

Responsabilidade:

- fornecer escuta contextual para paginas migradas;
- carregar configuracao de voz;
- iniciar escuta continua quando permitido;
- processar texto reconhecido;
- acionar `VoiceCommandController`;
- executar comandos globais via `VoiceGlobalCommandService`;
- despachar comandos de pagina via `VoiceCommandDispatcher`;
- registrar comandos reconhecidos;
- reiniciar escuta continua quando apropriado;
- observar ciclo de vida do app com `AppLifecycleListener`.

Estado atual:

- ja usa `VoiceSessionManager.startListening`, `stopListening` e `cancelListening`;
- ainda possui flags locais: `voiceOuvindo`, `voiceEscutaContinuaAtiva`, `voiceParadaManual`, `voiceExecutandoComando`, `voiceIaPensando`;
- ainda chama `VoiceListeningCoordinator` para fachada de release/restart;
- ainda depende de `StatefulWidget` e `setState`.

Direcao: manter como ponte enquanto as paginas migram para um modelo event-driven. No futuro, o mixin deve observar um estado central e apenas registrar handlers contextuais.

### 2.8 `RecordingRealtimeCoordinator`

Arquivo: `lib/features/editor/controllers/recording_realtime_coordinator.dart`

Responsabilidade:

- centralizar a orquestracao realtime da gravacao do editor;
- manter `RecordingRealtimeState`;
- iniciar gravacao real via `AudioRecordingService`;
- pausar e retomar gravacao;
- encerrar gravacao manualmente;
- encerrar automaticamente por silencio;
- monitorar amplitude do microfone;
- controlar playback via `AudioPlayerService`;
- impedir playback durante gravacao;
- registrar eventos no `VoiceSessionManager.diagnostics`;
- expor estado por `ChangeNotifier`;
- receber callbacks da UI para persistencia e historico.

Estado exposto:

- `recording`
- `paused`
- `playing`
- `processing`
- `currentPath`
- `startedAt`
- `currentAmplitude`
- `silenceMs`
- `statusMessage`

Capacidades derivadas:

- `canStartRecording`
- `canPauseRecording`
- `canResumeRecording`
- `canStopRecording`
- `canPlay`
- `canStopPlayback`

Decisao: o coordenador nao salva diretamente no banco. Ele recebe `RecordingFinalizer` como callback. Isso preserva compatibilidade com o `EditorPage`, que ainda conhece `usuario`, `projeto`, lista de faixas e historico. A meta futura e mover essa persistencia para um use case.

### 2.9 `AudioRecordingService`

Arquivo: `lib/features/editor/services/audio_recording_service.dart`

Responsabilidade:

- encapsular `package:record`;
- criar arquivo `.m4a` em diretorio local;
- iniciar, pausar, retomar, parar e cancelar gravacao;
- consultar amplitude;
- publicar modo gravacao no `VoiceSessionManager`;
- transicionar para `paused`/`recording` na state machine em pause/resume.

Decisao: o service e adaptador tecnico do plugin. Ele nao deve conhecer UI, banco, historico ou comandos.

### 2.10 `AudioPlayerService`

Arquivo: `lib/features/editor/services/audio_player_service.dart`

Responsabilidade:

- encapsular `just_audio`;
- validar caminho de arquivo;
- iniciar playback somente se `VoiceSessionManager.beginPlayback` permitir;
- encerrar ownership de playback ao completar, parar, pausar, falhar ou descartar;
- expor `playerStateStream`.

Decisao: playback agora participa da sessao global, o que prepara a futura camada de audio focus Android.

## 3. Estrutura de arquivos atualizada

```text
lib/features/voices/
  services/
    speech_service.dart
      Adaptador STT singleton. Debounce e dedupe de resultados.
    command_service.dart
      Parser deterministico local.
    custom_command_service.dart
      Comandos personalizados persistidos.
    ai_command_service.dart
      Fallback Gemini com JSON estruturado.
    voice_global_command_service.dart
      Comandos globais de configuracao/voz.
    voice_feedback_service.dart
      Feedback local simples.
    voice_permission_service.dart
      UX e checagem de permissao.

  controllers/
    voice_command_controller.dart
      Pipeline local -> custom -> IA.

  coordination/
    voice_state_machine.dart
      Estado canonico realtime.
    voice_session_manager.dart
      Autoridade central de sessao, ownership, STT, playback, recording e recovery.
    voice_diagnostics.dart
      Log estruturado em memoria.
    voice_listening_coordinator.dart
      Fachada de compatibilidade para codigo antigo.
    contextual_voice_listening_mixin.dart
      Mixin das paginas contextuais.
    voice_command_dispatcher.dart
      Despacho de comandos por pagina.
    voice_route_observer.dart
      Cancela/invalida STT em navegacao.
    voice_session_state.dart
      Estado local de UI/fase contextual.
    voice_page_owners.dart
      IDs estaveis de owners por tela.

lib/features/editor/
  controllers/
    recording_realtime_coordinator.dart
      Coordenador realtime de gravacao/playback/silencio.

  services/
    audio_recording_service.dart
      Adaptador `record`.
    audio_player_service.dart
      Adaptador `just_audio`.

  pages/
    editor_page.dart
      UI + intencoes + callbacks de persistencia. Nao deve ser dono operacional do audio.
```

## 4. Integracao atual entre modulos

Fluxo de STT contextual:

```text
Pagina com ContextualVoiceListeningMixin
  -> VoiceSessionManager.startListening(ownerId)
    -> VoiceSessionManager.claimListening(ownerId)
      -> VoiceStateMachine.listening
      -> VoiceDiagnostics.listeningStarted
    -> SpeechService.startListening(...)
      -> speech_to_text.listen(...)
  -> onResult(texto)
    -> VoiceCommandController.interpret(...)
    -> VoiceGlobalCommandService ou VoiceCommandDispatcher
    -> scheduleRecovery/restart se configuracao permitir
```

Fluxo de gravacao no editor:

```text
EditorPage.iniciarGravacao(comando)
  -> _pausarEscutaParaModoGravacao()
    -> VoiceSessionManager.enterRecordingMode(editor)
    -> VoiceSessionManager.cancelListening(editor)
  -> RecordingRealtimeCoordinator.startRecording(...)
    -> AudioRecordingService.startRecording()
      -> VoiceSessionManager.enterRecordingMode(editor)
      -> record.start(...)
    -> RecordingRealtimeState.recording=true
    -> Timer de silencio no coordenador
```

Fluxo de stop manual:

```text
EditorPage.encerrarGravacao(comando)
  -> RecordingRealtimeCoordinator.stopRecording(...)
    -> AudioRecordingService.stopRecording()
      -> VoiceSessionManager.exitRecordingMode(editor)
    -> RecordingFinalizer callback no EditorPage
      -> RecordingManagementService.createCompletedRecording(...)
      -> atualiza lista de faixas
    -> historico callback
  -> EditorPage._retomarEscutaContinuaAposModoGravacao()
```

Fluxo de stop automatico por silencio:

```text
RecordingRealtimeCoordinator._startSilenceMonitoring()
  -> Timer.periodic(500 ms)
  -> AudioRecordingService.getAmplitude()
  -> se amplitude <= -36 dB, acumula silenceMs
  -> se silenceMs >= configuracao, registra diagnostic
  -> stopRecording(automatic: true)
  -> callback onAutomaticStop para retomar escuta continua
```

Fluxo de playback:

```text
EditorPage.reproduzirFaixa(...)
  -> RecordingRealtimeCoordinator.play(...)
    -> AudioPlayerService.play(path)
      -> VoiceSessionManager.beginPlayback(editor)
        -> bloqueia se recording ativo
        -> cancela STT se STT ativo
        -> VoiceStateMachine.executing
      -> just_audio.play()
    -> RecordingRealtimeState.playing=true
```

## 5. Estado atual da UI

O `EditorPage` foi reduzido, mas ainda nao e uma camada pura de apresentacao. Hoje ele:

- observa `RecordingRealtimeCoordinator.state`;
- expoe getters derivados (`gravando`, `pausado`, `reproduzindo`, `carregandoAudio`);
- emite intencoes de gravacao e playback;
- ainda interpreta comandos de voz localmente;
- ainda registra historico;
- ainda finaliza e persiste gravacoes via callback;
- ainda coordena algumas transicoes de UI com `VoiceSessionState`.

Isso e uma melhoria importante, mas nao o ponto final. A proxima extracao deve mover persistencia/historico de gravacao para um use case ou service de aplicacao.

## 6. Decisoes arquiteturais relevantes

### ADR-RT-001: `VoiceSessionManager` como autoridade real

Problema: STT, recorder e playback eram acionados por caminhos diferentes, criando risco de dupla escuta, corrida de lifecycle e conflito de microfone.

Decisao: centralizar ownership e ciclo real de STT/playback/recording no manager.

Trade-off: durante a migracao, ainda existem adapters e estados locais. Isso reduz risco de regressao, mas exige disciplina para nao adicionar novas chamadas diretas ao STT nas paginas.

### ADR-RT-002: state machine canonica separada de UI state

Problema: estados de UI nao bastam para coordenar audio realtime.

Decisao: criar `VoiceStateMachine` com estados operacionais canonicos e manter `VoiceSessionState` temporariamente para compatibilidade visual.

Trade-off: ha duplicidade transitoria. O alvo e derivar UI state do snapshot canonico.

### ADR-RT-003: manter modo hibrido durante gravacao

Problema: `speech_to_text` e `record` competem pelo microfone no Android.

Decisao: durante gravacao real, STT e cancelado/suspenso e o microfone fica reservado ao recorder.

Trade-off: o editor ainda nao e 100% hands-free enquanto esta gravando. A parada por silencio compensa parte disso, mas comandos como "encerrar" durante captura ativa ainda nao sao confiaveis sem uma estrategia nativa/wake-word/audio focus.

### ADR-RT-004: playback entra na sessao global

Problema: playback podia concorrer com STT, gerar eco ou disputar foco.

Decisao: `AudioPlayerService` solicita playback ao `VoiceSessionManager`, que cancela STT se necessario e bloqueia playback durante gravacao.

Trade-off: ainda nao existe integracao nativa com Android Audio Focus; a regra e de aplicacao, nao de sistema operacional.

### ADR-RT-005: `RecordingRealtimeCoordinator` nao persiste diretamente

Problema: mover tudo de uma vez para fora do `EditorPage` aumentaria o risco de regressao.

Decisao: o coordenador controla realtime e recebe callbacks para salvar/historico.

Trade-off: `EditorPage` ainda contem parte do fluxo de aplicacao. A proxima fase deve criar um use case de finalizacao de gravacao.

## 7. Estado de validacao

No workspace atual:

- `git diff --check` passou, com avisos LF/CRLF em arquivos ja sujos;
- `dart format` travou por timeout no ambiente;
- `flutter analyze` travou por timeout no ambiente;
- a arquitetura nova ainda precisa de format/analyze/test antes de commit;
- precisa validacao manual em Android real.

Arquivos gerados/locais sujos continuam fora do escopo arquitetural:

- `.metadata`;
- `ios/Flutter/*`;
- `ios/Runner/GeneratedPluginRegistrant.*`.

