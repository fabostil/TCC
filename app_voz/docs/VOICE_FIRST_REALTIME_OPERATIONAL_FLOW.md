# Voice-First Realtime Operational Flow

Data: 2026-05-23
Branch: `feature/true-voice-first`

## Regras Operacionais

1. O fluxo legado e default.
2. `USE_STREAM_FIRST_AUDIO` nunca deve ficar ativo por padrao.
3. `SpeechService` nao deve consumir PCM externo.
4. `AudioRecordingService` nao deve ser removido.
5. Shadow Mode nao pode bloquear o pipeline principal.
6. Wake-word stub nao pode acionar STT/gravacao real.
7. Eventos experimentais devem ser observaveis antes de comandarem produto.

## Fluxo Legado Sem Flag

```text
Usuario abre Editor
  -> RecordingRealtimeCoordinator
    -> AudioRecordingService
      -> record.start(...)
      -> arquivo .m4a
  -> VAD legado por amplitude
  -> RecordingManagementService
    -> grava path .m4a e formato m4a
  -> just_audio toca arquivo
```

STT:

```text
SpeechService
  -> speech_to_text
  -> VoiceCommandController
  -> CommandService / Custom / Gemini
```

Durante gravacao, STT e pausado/cancelado.

## Fluxo Stream-First Com Flag

Comando:

```powershell
flutter run -d <androidDeviceId> --dart-define=USE_STREAM_FIRST_AUDIO=true
```

Fluxo:

```text
RecordingRealtimeCoordinator
  -> StreamFirstAudioRecordingService
    -> record.startStream(PCM16 16k mono)
    -> rawAudioChunks
    -> PcmWavFileWriter
      -> arquivo .wav
  -> RecordingManagementService
    -> salva path .wav e formato wav
```

Em paralelo:

```text
rawAudioChunks
  -> AudioStreamShadowRouter
    -> AudioPipelineChunkReceivedEvent
    -> AudioIsolateBridge.sendCommand(AUDIO_CHUNK)
      -> AudioPipelineIsolate
        -> StubWakeWordEngine
        -> AdaptiveSilenceVad
```

## Ciclo Do AudioPipelineIsolate

Start:

```text
AudioIsolateBridge.start()
  -> Isolate.spawn(startAudioPipeline)
  -> READY + SendPort
  -> AudioPipelineReadyEvent
```

Capture:

```text
START_CAPTURE
  -> captura ativa
  -> limpa accumulator
  -> reset VAD
  -> CAPTURE_STARTED
```

Chunk:

```text
AUDIO_CHUNK
  -> se nao capturando: ignora
  -> valida Uint8List
  -> acumula frames de 640 bytes
  -> converte frame para Int16List
  -> WakeWordEngine.processFrame(frame)
  -> AdaptiveSilenceVad.analyzeFrame(bytes)
```

Stop:

```text
STOP_CAPTURE
  -> captura inativa
  -> limpa accumulator
  -> reset VAD
  -> CAPTURE_STOPPED
```

Shutdown:

```text
SHUTDOWN
  -> dispose wake-word
  -> SHUTDOWN_COMPLETE
  -> fecha ReceivePort
```

## Wake-word Operacional

Estado atual:

```text
Int16List frame
  -> StubWakeWordEngine
    -> se padrao magico e cooldown OK
      -> WAKE_WORD_DETECTED
        -> AudioIsolateBridge
          -> VoiceWakeWordDetectedEvent
```

O evento:

- recebe novo `correlationId` com prefixo `wake_`;
- inclui `pipelineCorrelationId` nos metadados;
- inclui `detectedAt`;
- nao dispara comando estrutural.

## VAD Operacional

```text
Uint8List frame PCM16
  -> RMS
  -> noise floor
  -> adaptive threshold
  -> consecutive silent frames
  -> SILENCE_DETECTED
    -> SilenceDetectedEvent(isIsolateEngine: true)
```

Runtime:

- flag off: ignora isolate e usa legado;
- flag on: ignora legado e usa isolate.

## STT Streaming Operacional

Quando `USE_STREAM_FIRST_AUDIO=true`:

```text
AudioPipelineCaptureStartedEvent
  -> VoiceRuntimeEngine
    -> StreamingSpeechRecognizer.initializeRecognizer()
    -> startRecognition(correlationId)

AudioPipelineChunkReceivedEvent
  -> feedAudioChunk(chunk)

AudioPipelineCaptureStoppedEvent / Shutdown
  -> stopRecognition()
```

Escolha da implementacao:

- sem `STREAMING_STT_WEBSOCKET_URL`: `UnsupportedSpeechRecognizer`;
- com endpoint `ws://` ou `wss://`: `CloudStreamingSpeechRecognizer`.

## Cloud WebSocket Flow

```text
startRecognition
  -> WebSocket.connect(endpoint).timeout(...)
  -> listen(server messages)

feedAudioChunk
  -> webSocket.add(Uint8List)

server JSON
  -> parse text/transcript + isFinal
  -> SpeechResultReceivedEvent

erro/timeout
  -> SpeechListeningFailedEvent
  -> cleanup

stop/dispose
  -> closeMessage opcional
  -> webSocket.close()
```

## Recovery E Ownership

`VoiceRuntimeEngine`:

- rejeita mutacoes sem ownership valido;
- agenda recovery apos falha STT;
- limita tentativas via `RuntimeRecoveryPolicy`;
- degrada sistema quando budget esgota.

`VoiceRuntimeRegistry`:

- mantem sessao ativa;
- mantem contexto de rota;
- valida se sessao ainda e viva.

## Android Real - Fluxo De Validacao

Ainda pendente nesta base.

Roteiro:

```powershell
flutter devices
flutter run -d <androidDeviceId> --dart-define=USE_STREAM_FIRST_AUDIO=true
adb logcat -c
adb logcat
```

Validar:

- permissao de microfone;
- iniciar gravacao;
- chunks no Shadow Router;
- arquivo `.wav`;
- playback;
- silencio;
- isolate;
- dispose;
- troca de tela;
- recovery;
- sessao longa.

## Bugs Reais Conhecidos

- Sem Android conectado, nao ha hardening real.
- `flutter run` sem `-d` falha se houver multiplos targets.
- `speech_to_text` nao aceita PCM externo.
- STT legado e recorder disputam microfone.
- `flutter test` completo ainda falha em widget tests de auth/asset.

## CURRENT_ARCHITECTURE_STATUS

ESTAVEL:

- fluxo legado.

EXPERIMENTAL:

- fluxo Stream-First e isolate.

PLACEHOLDER:

- STT cloud e wake-word.

FUTURO:

- Audio Focus e hands-free real.

## NEXT_SESSION_BOOTSTRAP

Leia `SESSION_SUMMARY.md` e este arquivo.

Depois:

```powershell
dart analyze
flutter test --reporter expanded test/features/voices/realtime
git status --short
```

Para teste real, conectar Android e rodar com `USE_STREAM_FIRST_AUDIO=true`.
