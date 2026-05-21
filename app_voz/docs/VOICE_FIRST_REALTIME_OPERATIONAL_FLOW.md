# Voice-First Realtime Operational Flow

Data: 2026-05-20
Escopo: fluxo operacional atual de STT, gravacao, playback, ownership, recovery e diagnostico.

Este documento descreve como o sistema opera em tempo real no workspace atual. Ele deve ser lido junto com `VOICE_FIRST_REALTIME_ARCHITECTURE.md`.

## 1. Principios operacionais

O sistema segue estas regras de prioridade:

1. Gravacao real tem prioridade maxima sobre STT e playback.
2. STT nao deve rodar em paralelo com `record`.
3. Playback nao deve iniciar se gravacao estiver ativa.
4. Playback pode cancelar STT para evitar disputa de audio.
5. Recovery de STT so pode ocorrer se a sessao ainda for valida.
6. Owners antigos nao devem derrubar sessoes novas.
7. Paginas devem emitir intencoes, nao controlar diretamente o microfone.

## 2. Owners atuais

Os owners representam quem esta tentando controlar uma sessao de voz/audio. Exemplos:

- `VoicePageOwners.editor`;
- owners das paginas contextuais;
- owner passado ao `RecordingRealtimeCoordinator`;
- owners internos de services quando nao injetados.

O owner atual fica em `VoiceSessionManager.activeOwnerId`. O tipo de recurso fica em `VoiceSessionManager.audioOwnerType`.

Estados possiveis de recurso:

```text
none      nenhum recurso de audio controlado pela sessao
stt       escuta por speech-to-text ativa
recorder  gravacao real usando microfone
playback  reproducao de audio ativa
```

## 3. Ciclo de vida do STT

### 3.1 Inicio normal

O caminho correto atual e:

```text
Pagina/Mixin
  -> VoiceSessionManager.startListening(ownerId, callbacks)
    -> invalidateRecovery()
    -> claimListening(ownerId)
      -> canClaimListening(ownerId)
      -> activeOwnerId = ownerId
      -> audioOwnerType = stt
      -> VoiceStateMachine.listening
      -> VoiceDiagnostics.listeningStarted
    -> SpeechService.startListening(...)
```

`SpeechService.startListening`:

- inicializa permissao e plugin se necessario;
- para escuta anterior do plugin se ainda estiver ouvindo;
- limpa estado de debounce/dedupe;
- inicia `speech_to_text.listen`;
- usa `listenFor` de 2 minutos;
- usa `pauseFor` de 10 segundos;
- usa `ListenMode.dictation`;
- entrega parciais com debounce de 450 ms;
- evita entregar duplicatas em intervalo de 2 segundos.

### 3.2 Resultado reconhecido

Em paginas com `ContextualVoiceListeningMixin`:

```text
onResult(texto)
  -> processContextualVoiceInput(texto)
    -> voiceExecutandoComando = true
    -> VoiceSessionManager.markProcessing(...)
    -> VoiceCommandController.interpret(...)
      -> CommandService local
      -> CustomCommandService
      -> AiCommandService se necessario
    -> registra comando
    -> VoiceGlobalCommandService ou VoiceCommandDispatcher
    -> VoiceSessionManager.markExecuting(...)
    -> scheduleVoiceContinuousRestart()
```

No `EditorPage`, o fluxo ainda e proprio:

```text
onResult(texto)
  -> interpretarComando(texto)
    -> VoiceCommandController.interpret(...)
    -> comandos de gravacao/playback chamam intencoes do editor
```

Gargalo: o editor ainda nao usa `VoiceCommandDispatcher` como as paginas contextuais.

### 3.3 Status `done` ou `notListening`

Quando o STT encerra:

```text
onStatus(done/notListening)
  -> UI local marca idle
  -> scheduleRecovery ou scheduleContinuousRestart
```

O manager agenda recovery com:

- validacao de `generation`;
- condicao `shouldRecover`;
- validacao de `canClaimListening`;
- incremento de tentativas;
- chamada de `onRecover`.

### 3.4 Erro de STT

Quando `SpeechService` notifica erro:

```text
VoiceSessionManager.registerFailure(...)
  -> lastFailureReason = reason
  -> VoiceStateMachine.error
  -> VoiceDiagnostics.error
  -> scheduleRecovery(afterError)
```

O delay depois de erro e 2 segundos. O limite atual e 3 tentativas.

## 4. Ciclo de vida da gravacao

### 4.1 Preparacao no editor

Antes de gravar:

```text
EditorPage.iniciarGravacao()
  -> _pausarEscutaParaModoGravacao()
    -> VoiceSessionManager.enterRecordingMode(editor)
      -> invalidateRecovery()
      -> activeOwnerId = null
      -> audioOwnerType = recorder
      -> speech.cancelListening()
      -> VoiceStateMachine.recording
    -> se STT ativo:
      -> VoiceSessionManager.cancelListening(editor)
      -> delay 500 ms
```

O delay fixo de 500 ms ainda e uma solucao pragmatica para liberar o microfone no Android antes de iniciar `record`.

### 4.2 Inicio real

```text
RecordingRealtimeCoordinator.startRecording()
  -> se ja recording: status informativo
  -> se processing: status informativo
  -> se playing: stopPlayback()
  -> diagnostics.record(recordingStarted, recording_intent)
  -> state.processing = true
  -> AudioRecordingService.startRecording()
    -> VoiceSessionManager.enterRecordingMode(ownerId)
    -> AudioRecorder.hasPermission()
    -> cria diretorio /gravacoes
    -> AudioRecorder.start(AAC LC, 128 kbps, 44100 Hz)
  -> state.recording = true
  -> state.currentPath = path
  -> state.startedAt = now
  -> state.currentAmplitude = -160
  -> inicia monitoramento de silencio
  -> historico: gravacao_iniciada
```

### 4.3 Pausa

```text
RecordingRealtimeCoordinator.pauseRecording()
  -> valida recording e !paused
  -> state.processing = true
  -> AudioRecordingService.pauseRecording()
    -> AudioRecorder.pause()
    -> VoiceStateMachine.paused
  -> cancela timer de silencio
  -> state.paused = true
  -> historico: gravacao_pausada
```

Durante pausa, a arquitetura ja representa `paused`, mas ainda nao ha politica madura para abrir uma janela STT confiavel. Isso e uma oportunidade futura.

### 4.4 Retomada

```text
RecordingRealtimeCoordinator.resumeRecording()
  -> valida recording && paused
  -> AudioRecordingService.resumeRecording()
    -> AudioRecorder.resume()
    -> VoiceStateMachine.recording
  -> state.paused = false
  -> reinicia monitoramento de silencio
  -> historico: gravacao_retomada
```

### 4.5 Stop manual

```text
RecordingRealtimeCoordinator.stopRecording(automatic: false)
  -> cancela timer de silencio
  -> state.processing = true
  -> AudioRecordingService.stopRecording()
    -> AudioRecorder.stop()
    -> VoiceSessionManager.exitRecordingMode(ownerId)
  -> chama RecordingFinalizer
    -> EditorPage cria Gravacao via RecordingManagementService
    -> insere faixa na UI
  -> reseta estado realtime
  -> historico: gravacao_finalizada
  -> EditorPage retoma escuta continua se configuracao permitir
```

### 4.6 Stop automatico por silencio

O timer vive no `RecordingRealtimeCoordinator`, nao mais no `EditorPage`.

Parametros atuais:

- intervalo: 500 ms;
- threshold: `-36.0 dB`;
- limite: configuracao `tempoSilencioSegundos * 1000`;
- default inicial: 6000 ms.

Fluxo:

```text
Timer.periodic(500 ms)
  -> se !recording ou paused ou processing: ignora
  -> se automaticSilenceStop=false: ignora
  -> AudioRecordingService.getAmplitude()
  -> se amplitude <= -36 dB: soma 500 ms
  -> senao: zera contador
  -> se contador >= limite:
    -> diagnostics.record(recordingStopped, automatic_silence_stop)
    -> stopRecording(automatic: true)
    -> callback onAutomaticStop
```

Observabilidade atual:

- amplitude atual fica em `RecordingRealtimeState.currentAmplitude`;
- silencio acumulado fica em `RecordingRealtimeState.silenceMs`;
- UI renderiza esses valores, mas nao os controla.

## 5. Ciclo de vida do playback

### 5.1 Inicio

```text
RecordingRealtimeCoordinator.play(path, name)
  -> valida path
  -> bloqueia se recording
  -> state.processing = true
  -> AudioPlayerService.play(path)
    -> valida arquivo
    -> VoiceSessionManager.beginPlayback(ownerId)
      -> se recorder ativo: bloqueia
      -> se stt ativo: cancelListening(...)
      -> activeOwnerId = ownerId
      -> audioOwnerType = playback
      -> VoiceStateMachine.executing
      -> diagnostics.playbackStarted
    -> just_audio.setFilePath()
    -> just_audio.play()
  -> state.playing = true
  -> historico: gravacao_reproduzida
```

### 5.2 Encerramento

Playback termina por:

- `stopPlayback`;
- `pause`;
- fim natural do audio;
- dispose;
- falha ao tocar.

O `AudioPlayerService` chama `VoiceSessionManager.endPlayback`, que:

- libera `audioOwnerType` se for playback;
- limpa `activeOwnerId` se pertence ao owner;
- transiciona state machine para `idle`;
- registra `playbackStopped`.

## 6. Navegacao e lifecycle

`main.dart` registra `VoiceRouteObserver`.

`VoiceRouteObserver`:

- em `didPush`, chama `VoiceListeningCoordinator.onRouteDidPush`;
- em `didPop`, chama `VoiceListeningCoordinator.onRouteDidPop`;
- em `didReplace`, trata como push.

Como `VoiceListeningCoordinator` delega ao manager:

- push invalida recovery e cancela STT;
- pop invalida recovery.

Gargalo: retomada ao voltar ainda depende de cada pagina/mixin. O sistema ainda nao possui um registro global de rota ativa + handler ativo.

## 7. Estado realtime do EditorPage

O `EditorPage` nao possui mais timer de silencio nem service direto de recorder/player. Ele possui getters derivados:

```text
gravando          -> recordingState.recording
pausado           -> recordingState.paused
reproduzindo      -> recordingState.playing
carregandoAudio   -> recordingState.processing
nivelAudioAtual   -> recordingState.currentAmplitude
tempoSilencioMs   -> recordingState.silenceMs
caminhoAtual      -> recordingState.currentPath
```

Intencoes atuais da pagina:

- `iniciarGravacao`;
- `pausarGravacao`;
- `retomarGravacao`;
- `encerrarGravacao`;
- `reproduzirProjeto`;
- `reproduzirFaixa`;
- `pararReproducao`.

Responsabilidades que ainda ficaram no `EditorPage`:

- interpretar comandos do editor;
- registrar comandos de voz;
- registrar historico;
- gerar nome unico da gravacao;
- finalizar e persistir gravacao;
- atualizar lista local de faixas;
- retomar escuta continua apos gravacao;
- coordenar mensagens de UI.

## 8. Recovery atual

O recovery atual e suficiente para reduzir falhas simples, mas ainda nao e uma arquitetura completa de background recovery.

O que ja existe:

- delay por motivo;
- limite de tentativas;
- invalidacao por geracao;
- verificacao de condicao antes de recuperar;
- verificacao de ownership antes de recuperar;
- log de agendado/tentado/ignorado.

O que falta:

- politica de backoff progressivo;
- diferenciar erro transitorio, permissao negada, engine indisponivel e audio focus;
- recovery global independente de pagina;
- retry observavel na UI;
- metricas persistentes;
- testes de corrida com timers falsos.

## 9. Falhas esperadas e comportamento atual

| Falha | Comportamento atual | Risco restante |
| --- | --- | --- |
| Permissao de microfone negada no STT | `SpeechService.initialize` retorna false e aciona erro | UX depende da pagina que chamou |
| `record` sem permissao | `AudioRecordingService` sai do modo gravacao e lança excecao | Editor mostra erro, precisa teste real |
| STT timeout | UI marca erro e agenda recovery | Pode repetir ate limite; nao ha classificacao rica |
| Troca de rota durante STT | observer cancela/invalida | Retomada depende da pagina visivel |
| Playback durante gravacao | bloqueado no manager | Mensagem ainda generica |
| Gravacao durante playback | coordenador para playback antes de gravar | Precisa teste Android |
| Dispose durante gravacao | coordinator dispose chama dispose dos services | Salvamento seguro ao sair depende de `PopScope`/confirmacao |

## 10. Checklist operacional para retomada

Antes de continuar implementacao:

1. Rodar `git status --short`.
2. Separar arquivos gerados/locais dos arquivos de arquitetura.
3. Rodar `dart format` nos arquivos alterados.
4. Rodar `flutter analyze`.
5. Rodar testes de coordination/editor quando disponiveis.
6. Validar manualmente em Android real:
   - Home ouvindo sem clique;
   - navegar por voz;
   - abrir editor;
   - iniciar gravacao por voz;
   - stop automatico por silencio;
   - retomada da escuta apos gravacao;
   - playback sem STT concorrente;
   - troca de rota sem dupla escuta.

