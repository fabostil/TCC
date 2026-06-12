# Voice-First Realtime Roadmap And Risk Register

Data: 2026-05-23
Branch: `feature/true-voice-first`

## Estado Atual

A arquitetura realtime saiu da fase apenas conceitual. Ja existem:

- isolate de audio;
- bridge;
- event bus;
- runtime engine;
- shadow router;
- stream-first recorder;
- WAV writer;
- VAD adaptativo;
- STT facade;
- cloud WebSocket adapter generico;
- wake-word stub.

Ainda nao existe:

- hardening Android real completo;
- provider STT real;
- wake-word real;
- Audio Focus Android;
- hands-free total.

## Roadmap Imediato

### R1 - Fechar Gate De Testes

Prioridade: alta.

Tarefas:

- Corrigir widget tests de auth/asset.
- Confirmar `flutter test` completo.
- Manter `dart analyze` sem issues.
- Manter `test/features/voices/realtime` verde.

Motivo: nao evoluir provider/wake-word com suite global quebrada.

### R2 - Hardening Android Real

Prioridade: critica.

Comando:

```powershell
flutter run -d <androidDeviceId> --dart-define=USE_STREAM_FIRST_AUDIO=true
```

Checklist:

- gravacao Stream-First;
- WAV real;
- playback WAV;
- VAD adaptativo;
- isolate;
- Shadow Mode;
- STT fallback Unsupported quando sem endpoint;
- dispose;
- recovery;
- troca de tela;
- long session.

Saida esperada:

- checklist preenchido;
- logs salvos;
- bugs reais priorizados.

### R3 - Diagnostics UI

Prioridade: media/alta.

Tarefas:

- tela interna de eventos realtime;
- filtro por correlation;
- exportar timeline;
- destacar erros/degraded;
- mostrar eventos de wake-word e silencio lado a lado.

### R4 - Provider STT Real

Prioridade: media.

Pre-condicoes:

- Android Stream-First validado.
- Endpoint/provedor escolhido.
- Politica de custo e auth definida.

Tarefas:

- criar adapter especifico;
- testar protocolo com transporte mockado;
- configurar endpoint por dart-define;
- validar latencia real.

### R5 - Wake-word Real

Prioridade: futura.

Pre-condicoes:

- runtime observado em Android;
- Audio Focus desenhado;
- politica de estados permitidos aprovada;
- CPU/bateria medidos.

Tarefas:

- escolher engine offline;
- criar adapter FFI/nativo;
- carregar keyword file;
- substituir stub por implementacao real atras do contrato;
- manter cooldown e telemetria.

### R6 - Android Audio Focus

Prioridade: alta antes de always-on real.

Tarefas:

- adapter Android/Kotlin;
- focus gain/loss/transient/duck;
- route/device changes;
- chamadas/interrupcoes;
- eventos no runtime.

## Riscos

| Risco | Severidade | Estado | Mitigacao |
| --- | --- | --- | --- |
| Regressao no legado | Alta | controlado | flags off por padrao |
| Android real nao validado | Alta | aberto | executar hardening |
| `record.startStream` instavel | Alta | aberto | fallback legado |
| WAV com incompatibilidade real | Alta | aberto | playback Android |
| Cloud STT sem protocolo | Media | aberto | adapter especifico |
| Wake-word falso positivo | Media | mitigado no stub | cooldown + engine real |
| Event bus reentrante | Media | corrigido | fila interna + testes |
| Audio Focus ausente | Alta | aberto | adapter nativo futuro |
| Suite global quebrada | Media | aberto | corrigir auth widget tests |

## O Que Nao Fazer

- Nao remover `SpeechService`.
- Nao remover `AudioRecordingService`.
- Nao ativar `USE_STREAM_FIRST_AUDIO` por padrao.
- Nao conectar wake-word a comandos reais nesta etapa.
- Nao colocar API key no codigo.
- Nao hardcodar endpoint STT.
- Nao substituir VAD legado antes do hardening.
- Nao criar provider STT real sem contrato/teste mockado.

## CURRENT_ARCHITECTURE_STATUS

ESTAVEL:

- Produto Android legado.
- Parser local.
- Gemini opcional.
- Gravacao `.m4a`.
- Playback.
- Banco v8.

EXPERIMENTAL:

- Stream-First.
- WAV writer.
- Shadow Mode.
- Audio isolate.
- VAD adaptativo.
- Runtime arbitration.
- Telemetry/tracing.

PLACEHOLDER:

- Unsupported STT.
- Cloud WebSocket STT generico.
- Wake-word stub.

FUTURO:

- STT cloud real.
- Wake-word real.
- Audio Focus.
- Diagnostics UI.
- Runtime hands-free 100%.

## NEXT_SESSION_BOOTSTRAP

Sequencia recomendada:

```powershell
git branch --show-current
git status --short
dart analyze
flutter test --reporter expanded test/features/voices/realtime
flutter devices
```

Se houver Android:

```powershell
flutter run -d <androidDeviceId> --dart-define=USE_STREAM_FIRST_AUDIO=true
```

Se nao houver Android:

1. corrigir `flutter test` completo;
2. revisar diffs;
3. preparar commits pequenos;
4. nao avançar para provider/wake-word real.
