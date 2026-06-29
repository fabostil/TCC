# Voice-First Realtime Architecture

Data: 2026-05-23
Branch: `feature/true-voice-first`
Status: experimental, integrado por feature flags, sem substituir o fluxo legado por padrao.

## Objetivo

Criar uma arquitetura realtime capaz de evoluir o app para controle hands-free, mantendo risco baixo:

- plano de dados de audio isolado;
- plano de controle por eventos;
- telemetria diferencial;
- Stream-First opcional;
- VAD adaptativo;
- STT streaming por estrategia;
- wake-word offline local futura;
- fallback legado intacto.

## Principio De Seguranca

O fluxo legado de producao nao deve ser removido:

- `SpeechService` continua STT padrao.
- `AudioRecordingService` continua gravacao padrao.
- parada por silencio legado continua ativa quando a flag esta desligada.
- controles manuais continuam obrigatorios.

O realtime deve ser observavel antes de ser autoritativo.

## Visao Em Camadas

```text
App/UI
  -> RecordingRealtimeCoordinator
    -> AudioRecordingCapture
      -> AudioRecordingService (.m4a legado)
      -> StreamFirstAudioRecordingService (.wav experimental)

rawAudioChunks
  -> AudioStreamShadowRouter
    -> AudioIsolateBridge
      -> AudioPipelineIsolate
        -> WakeWordEngine
        -> AdaptiveSilenceVad

VoiceRealtimeEventBus
  -> VoiceRuntimeEngine
  -> VoiceResponseBridge
  -> RuntimeTelemetryTracer
  -> VoiceDiagnostics
  -> StreamingSpeechRecognizer
```

## Text-To-Speech Output

`VoiceResponseBridge` transforma intents, falhas e confirmacoes em texto falado
por uma implementacao de `TextToSpeechEngine`.

Composicao atual:

- testes e debug: `StubTextToSpeechEngine`, injetado explicitamente ou escolhido
  pelo `VoiceRealtimeEcosystem`;
- release: `FlutterTtsEngine`, adapter seguro para o canal nativo
  `flutter_tts`;
- fallback: se o plugin nativo nao estiver registrado ou falhar na
  configuracao, o adapter publica degradacao e volta para o stub.

Contrato operacional:

- idioma preferencial `pt-BR`, com tentativa de fallback para `pt-PT`;
- `speechRate` padrao `0.5`;
- `pitch` padrao `1.0`;
- `speak()` chama `stop()` antes de qualquer nova sintese para substituir a
  fala ativa e evitar fila de audio acumulada.

Dependencia nativa: `flutter_tts` esta listado no `pubspec.yaml`. O adapter
continua fail-safe em testes e debug, e deve ser validado em aparelho real para
confirmar sintese nativa Android/iOS.

## Android Foreground Service

`VoiceRealtimeEcosystem` recebe `VoiceForegroundService` por injecao. Em testes
e debug, a composicao default usa `StubVoiceForegroundService` para nao abrir
Platform Channels. Em release Android, a composicao default tenta
`AndroidVoiceForegroundService`.

O adapter de producao e fail-safe:

- evita inicializacoes duplicadas;
- `stopService()` e idempotente;
- publica `VoiceSystemDegradedEvent` se o canal nativo falhar;
- propaga a falha ao ecossistema, que mantem runtime, isolate e bus ativos sem
  marcar o foreground como iniciado.

Dependencia nativa: `flutter_foreground_task` esta listado no `pubspec.yaml`.
O arquivo `AndroidManifest.xml` declara:

- `android.permission.FOREGROUND_SERVICE`;
- `android.permission.FOREGROUND_SERVICE_MICROPHONE`;
- `android.permission.RECORD_AUDIO`.
- `android.permission.POST_NOTIFICATIONS`;
- o servico Android do plugin com
  `android:foregroundServiceType="microphone"`.

Em Android 13+, a permissao de notificacao deve ser solicitada em runtime antes
de iniciar o foreground service em fluxo real de aparelho.

## AudioRecordingCapture

Contrato compartilhado entre o recorder legado e o stream-first.

Responsabilidade:

- preservar API de gravacao;
- expor `rawAudioChunks`;
- permitir trocar implementacao por flag;
- evitar quebrar o editor.

Implementacoes:

- `AudioRecordingService`: legado, `.m4a`, default.
- `StreamFirstAudioRecordingService`: experimental, PCM stream, `.wav`.

## Stream-First Audio

`StreamFirstAudioRecordingService`:

- normaliza path de saida para `.wav`;
- chama `record.startStream(RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1))`;
- publica chunks em `rawAudioChunks`;
- escreve chunks via `PcmWavFileWriter`;
- cancela subscriptions no stop/cancel/dispose;
- retorna o path `.wav` final em `stopRecording()`.

Ativacao:

```powershell
--dart-define=USE_STREAM_FIRST_AUDIO=true
```

Padrao:

```text
USE_STREAM_FIRST_AUDIO=false
```

## WAV Persistence

`PcmWavFileWriter`:

- abre `RandomAccessFile` com `FileMode.write`;
- escreve header RIFF/WAVE de 44 bytes;
- usa PCM linear 16 bits;
- atualiza `ChunkSize` e `Subchunk2Size` no fechamento;
- rejeita `writeChunk` apos close;
- fecha descritores em erro.

Motivo: PCM puro escrito diretamente em disco nao seria arquivo WAV valido.

## Shadow Mode

`AudioStreamShadowRouter`:

- assina `rawAudioChunks`;
- publica `AudioPipelineChunkReceivedEvent`;
- envia `AUDIO_CHUNK` para `AudioIsolateBridge`;
- descarta silenciosamente se a bridge estiver indisponivel;
- nao acumula fila infinita;
- nao altera persistencia nem STT legado.

Objetivo: comparar sinais do isolate antes de substituir o motor real.

## AudioPipelineIsolate

Arquivo: `lib/features/voices/realtime/infrastructure/audio_pipeline_isolate.dart`.

Comandos:

- `START_CAPTURE`
- `STOP_CAPTURE`
- `PING`
- `SHUTDOWN`
- `AUDIO_CHUNK`

Mensagens:

- `READY`
- `CAPTURE_STARTED`
- `CAPTURE_STOPPED`
- `PONG`
- `SHUTDOWN_COMPLETE`
- `ERROR`
- `SILENCE_DETECTED`
- `WAKE_WORD_DETECTED`

O isolate:

- ignora chunks se captura nao esta ativa;
- acumula bytes em frames fixos;
- converte frame para `Int16List` para wake-word;
- analisa VAD adaptativo;
- emite mensagens map-based para bridge.

## Adaptive VAD

`AdaptiveSilenceVad`:

- espera PCM16 little-endian;
- frame default: 20 ms, 16 kHz, mono, 640 bytes;
- calcula RMS;
- rastreia noise floor;
- aplica margem sobre o ruido;
- emite silencio quando frames silenciosos consecutivos atingem limite.

O VAD adaptativo roda no isolate. O VAD legado nao foi removido.

## Wake-word Infrastructure

Contrato:

```dart
abstract class WakeWordEngine {
  Future<void> init(String keywordPath, double sensitivity);
  bool processFrame(Int16List frame);
  Future<void> dispose();
}
```

Implementacao atual:

- `StubWakeWordEngine`;
- Dart puro;
- detecta padrao de teste nos primeiros samples;
- cooldown para evitar cascatas;
- emite `VoiceWakeWordDetectedEvent` via bridge;
- nao ativa sessao real.

Futuro:

- adapter FFI/binario C;
- keyword real;
- tuning de sensibilidade;
- politicas de CPU/bateria.

## AudioIsolateBridge

Responsabilidades:

- iniciar isolate;
- receber `SendPort`;
- publicar `AudioPipelineReadyEvent`;
- enviar comandos;
- traduzir mensagens em eventos tipados;
- fazer shutdown limpo;
- emitir erro quando indisponivel.

Traducoes importantes:

- `SILENCE_DETECTED` -> `SilenceDetectedEvent(isIsolateEngine: true)`
- `WAKE_WORD_DETECTED` -> `VoiceWakeWordDetectedEvent`

## VoiceRealtimeEventBus

Barramento operacional:

- timeline circular;
- stream broadcast;
- cancelamento por correlation chain;
- publicacao reentrante via fila interna.

Eventos atuais incluem audio, silence, speech, wake-word, recovery, ownership e degradacao.

## VoiceRuntimeEngine

Responsabilidades:

- observar eventos realtime;
- arbitrar silencio por flag;
- iniciar/parar `StreamingSpeechRecognizer`;
- alimentar chunks correlacionados;
- gerar `StopVoiceCaptureRequestedEvent`;
- preservar `correlationId`;
- aplicar `RuntimeRecoveryPolicy`;
- respeitar `VoiceRuntimeRegistry`.

Arbitragem:

```text
USE_STREAM_FIRST_AUDIO=false
  -> processa SilenceDetectedEvent legado/isIsolateEngine=false

USE_STREAM_FIRST_AUDIO=true
  -> processa SilenceDetectedEvent do isolate/isIsolateEngine=true
```

## StreamingSpeechRecognizer

Contrato de STT streaming:

- `initializeRecognizer`
- `startRecognition`
- `feedAudioChunk`
- `stopRecognition`
- `dispose`

Implementacoes:

- `UnsupportedSpeechRecognizer`: noop seguro.
- `CloudStreamingSpeechRecognizer`: WebSocket generico testavel.

`CloudStreamingSpeechRecognizer`:

- usa `WebSocket.connect` no transporte nativo;
- aceita transporte injetavel nos testes;
- envia `Uint8List` como binario;
- fecha socket no stop/dispose;
- publica `SpeechResultReceivedEvent`;
- publica `SpeechListeningFailedEvent` em erro/timeout.

Sem provider real ainda.

## Telemetry And Tracing

`RuntimeTelemetryTracer`:

- registra eventos;
- reconstrói cadeia por `correlationId` e `causationId`;
- permite comparar VAD legado vs isolate.

`VoiceDiagnostics`:

- espelha eventos para diagnostico em memoria;
- ainda precisa UI.

## Feature Flags

```powershell
USE_STREAM_FIRST_AUDIO
STREAMING_STT_WEBSOCKET_URL
STREAMING_STT_CLOSE_MESSAGE
GEMINI_API_KEY
GEMINI_MODEL
GOOGLE_SERVER_CLIENT_ID
```

## Limites Atuais

- Android real ainda nao validado nesta sessao.
- Cloud STT sem provider.
- Wake-word real ausente.
- Audio Focus Android ausente.
- Diagnostics UI ausente.
- `flutter test` completo ainda tem falha em widget tests de auth/asset.

## CURRENT_ARCHITECTURE_STATUS

ESTAVEL:

- legado de voz/audio/produto.

EXPERIMENTAL:

- isolate, shadow, stream-first, VAD, runtime, telemetry.

PLACEHOLDER:

- STT cloud generico, wake-word stub.

FUTURO:

- provider STT, wake-word real, Audio Focus.

## NEXT_SESSION_BOOTSTRAP

Comandos de verificacao:

```powershell
git status --short
dart analyze
flutter test --reporter expanded test/features/voices/realtime
```

Para Android:

```powershell
flutter devices
flutter run -d <androidDeviceId> --dart-define=USE_STREAM_FIRST_AUDIO=true
```

Nao ativar Stream-First por default antes do hardening Android.
