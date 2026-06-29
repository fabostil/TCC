# Arquitetura de Voz e Áudio — Assistente Musical

Documento de referência para evolução **incremental** da base voice-first existente.
**Não substitui** `CommandService`, `VoiceCommandController` nem o modo híbrido do editor — estabiliza e centraliza em cima deles.

Última revisão: 2026-05-18
Baseline validada: `flutter analyze` sem issues; `flutter test` — 26 testes passando.

## Fase 2 — Implementado

| Entrega | Arquivo(s) |
|---------|----------------|
| `ContextualVoiceListeningMixin` | `coordination/contextual_voice_listening_mixin.dart` |
| `VoiceCommandDispatcher` | `coordination/voice_command_dispatcher.dart` |
| Telas migradas | dashboard, historico, configuracoes, minhas_gravacoes, meus_projetos, projeto_detalhes, detalhes_gravacao |
| Pendente Fase 2 | `home_page`, `editor_page`, `voice_page` (logica especial / modo gravacao) |

## Fase 1 — Implementado

| Entrega | Arquivo(s) |
|---------|----------------|
| `SpeechService` singleton | `lib/features/voices/services/speech_service.dart` |
| Coordenador de escuta (owner, recording mode, reinício) | `lib/features/voices/coordination/voice_listening_coordinator.dart` |
| IDs de owner por tela | `lib/features/voices/coordination/voice_page_owners.dart` |
| Cancelamento STT ao empilhar rotas | `lib/features/voices/coordination/voice_route_observer.dart` + `main.dart` |
| Páginas migradas | Home, Dashboard, Histórico, Projetos, Gravações, Configurações, Editor, VoicePage |

Delays unificados: **700 ms** (normal) / **2 s** (após erro).

---

## 1. Princípio de decisão

| Prioridade | Ação |
|------------|------|
| 1 | Estabilizar o que já existe |
| 2 | Corrigir bugs e duplicações |
| 3 | Melhorar arquitetura (coordenador, estados) |
| 4 | Preparar extensão para wake word offline |
| 5 | Documentar entregas e evolução futura (TCC) |

**Rejeitado neste ciclo:** reescrever a stack de voz do zero ou trocar `speech_to_text` sem necessidade comprovada.

---

## 2. O que já está sólido (manter)

```text
SpeechService (STT)
  → VoiceCommandController
      → CommandService (local, offline)
      → CustomCommandService (SQLite)
      → AiCommandService (Gemini, fallback)
  → VoiceGlobalCommandService (configurações)
  → Página contextual (switch por VoiceCommandType)
```

- Parser local extenso (`VoiceCommandType`, ~45 intents).
- Comandos contextuais por tela (cada page trata subset no `switch`).
- Escuta contínua com reinício após `done` / `notListening`.
- Modo híbrido no **Editor**: STT pausado enquanto `record` captura áudio.
- Testes unitários na cadeia interpretação (local + IA + models).

---

## 3. Avaliação do modo híbrido atual (Editor)

### Implementação

- `EditorInteractionMode`: `normal` | `recording`.
- Antes de gravar: `_pausarEscutaParaModoGravacao()` → `cancelListening()` + delay 500 ms.
- Durante `gravando`: `alternarMicrofone()` não inicia STT; UI informa uso manual.
- Após encerrar/cancelar: `_retomarEscutaContinuaAposModoGravacao()` se config permitir.
- Monitor de silêncio usa amplitude do `record`, não o STT.

### Veredito

**Bem implementado para o conflito principal Android (STT × `record`).**
É a abordagem correta para apps voice-first com captura musical (mesma família de trade-off de assistentes que pausam reconhecimento durante TTS/gravação).

### Lacunas conhecidas

| Lacuna | Impacto | Evolução sugerida |
|--------|---------|-------------------|
| Comandos de voz **impossíveis** enquanto `gravando` ou `pausado` | Hands-free no estúdio limitado a botões | Fase 2: janela STT só em `pausado` (mic livre) ou PTT dedicado |
| `reproduzindo` não bloqueia STT explicitamente em todas as paths | Possível eco / comando durante playback | Tratar `AudioFocus` + suspender STT ao reproduzir |
| Delays de retomada fixos (500 ms–2 s) | Retomada lenta ou corrida em devices lentos | Centralizar backoff no coordenador |
| Navegação por voz no editor redireciona para “assistente” | OK para estabilidade; documentar no TCC | Manter até existir coordenador global |

---

## 4. Conflitos microfone (STT × gravação × reprodução)

### Causa raiz

No Android, **um único pipeline de captura** costuma ser exclusivo entre:

- `speech_to_text` (reconhecimento),
- `package:record` (AAC),
- eventualmente outros plugins.

### Onde ainda há risco

1. **11 instâncias de `SpeechService`** (uma por página) — estado de debounce/`_initialized` duplicado; plugin subjacente pode ser único, mas callbacks e reinícios competem.
2. **Pilha de navegação:** `HomePage` permanece montada; filha inicia escuta no `initState` sem garantir que a pai parou (mitigado parcialmente por `_pararEscutaAntesDeNavegar` na Home).
3. **Páginas sem `dispose` explícito** parando STT — dependem de `stop` ao sair; risco de escuta fantasma.
4. **Gravação pausada:** `gravando == true` mantém STT bloqueado — mic livre mas sem comandos por voz.

### Mitigação evolutiva (sem big-bang)

1. `SpeechService` → **singleton** ou serviço injetado único.
2. `VoiceSessionCoordinator` — único dono de `start/stop/cancel` do STT.
3. Regra: **ao `Navigator.push`, coordenador transfere sessão** da rota anterior para a nova (ou suspende globalmente).
4. Editor publica `VoiceAudioMode.recording | idle` para o coordenador.

---

## 5. Wake word offline (viabilidade futura)

### Faz sentido?

**Sim, como camada adicional**, não como substituto do `CommandService`.

### Por que não agora

- Wake word exige detector leve sempre ativo (Porcupine, Vosk keyword spotter, ou modelo custom TensorFlow Lite).
- Durante gravação real, wake word também competiria pelo mic — mesma regra do modo híbrido: **desligar detector enquanto `record` ativo**.
- `speech_to_text` contínuo não é wake word; é caro e conflita com gravação.

### Preparação na arquitetura atual (Fase 4)

Definir interface sem implementar engine:

```dart
abstract class VoiceWakeWordEngine {
  Future<void> start({required void Function() onWake});
  Future<void> stop();
  bool get isRunning;
}
```

Fluxo alvo:

```text
[idle] → WakeWordEngine ouvindo palavra-gatilho
      → onWake → VoiceSessionCoordinator abre janela STT curta
      → CommandService / IA → ação
      → [recording] → WakeWord + STT OFF, só record
```

**TCC:** documentar como *evolução futura* com requisito não funcional de baixa latência e operação offline.

---

## 6. Reduzir dependência de STT contínuo durante gravações

| Estratégia | Descrição |
|------------|-----------|
| **Modo híbrido (atual)** | STT off + UI manual + parada por silêncio — **manter** |
| **Push-to-talk (PTT)** | Botão grande “comando” no editor pausado — baixo risco |
| **Janela de comando pós-pausa** | Ao pausar gravação, retomar STT por N segundos só para “retomar/encerrar” |
| **Comandos só manuais em recording** | Estado atual — aceitar para TCC v1 com limitação documentada |
| **Wake word pós-gravação** | Só em idle — Fase 4 |

**Não recomendado:** manter `speech_to_text.listen` em paralelo com `record.start` no mesmo device.

---

## 7. Centralização de estados de voz

### Estado atual (fragmentado)

Cada página mantém cópias de:

- `_ouvindo`, `_escutaContinuaAtiva`, `_paradaManualEscuta`, `_executandoComandoVoz`, `_iaPensando`
- `_reiniciarEscutaContinuaSeNecessario()` (delay 2 s na maioria; Home usa 700 ms)
- `_executarComandoVoz` + `switch` contextual

`VoiceStatusBar` expõe só: ouvindo + IA pensando.

### Modelo alvo (Fase 3)

```dart
enum VoiceSessionPhase {
  idle,           // microfone livre, escuta desligada
  listening,      // STT ativo
  processing,     // debounce / aguardando final
  interpreting,   // CommandService / custom / IA
  recording,      // record ativo — STT proibido
  recordingPaused,// record pausado — STT opcional (política)
  speaking,       // TTS ou playback com foco de áudio
  error,          // permissão, timeout, engine
  suspended,      // navegação / diálogo / confirmação
}
```

`VoiceSessionCoordinator` (ChangeNotifier ou similar):

- único `SpeechService`;
- expõe `phase`, `statusMessage`, `micOwner` (`stt` | `recorder` | `none`);
- métodos: `requestListen(context)`, `releaseListen()`, `enterRecordingMode()`, `exitRecordingMode()`;
- política única de reinício (backoff configurável).

Páginas passam a **observar** o coordenador e registrar **handlers contextuais** (`VoiceCommandHandler` por rota), em vez de duplicar STT.

---

## 8. Remover duplicação de handlers

### Situação

~8–10 páginas com blocos quase idênticos (~150–250 linhas cada): escuta, reinício, interpret, global commands, registro `ComandoVoz`.

### Abordagem incremental (baixo risco)

| Fase | Entrega | Risco |
|------|---------|-------|
| **2a** | Extrair `VoiceListeningMixin` ou `ContextualVoicePage` base com escuta/reinício/suspender | Baixo |
| **2b** | Extrair `VoiceCommandDispatcher` com `Map<VoiceCommandType, Future<void> Function()>` por tela | Médio |
| **2c** | Migrar páginas uma a uma; manter `switch` antigo até paridade | Baixo |
| **3** | `VoiceSessionCoordinator` substitui mixin | Médio |

**Ordem sugerida de migração:** `dashboard` → `historico` → `minhas_gravacoes` → `meus_projetos` → `projeto_detalhes` → `detalhes_gravacao` → `configuracoes` → `home` → `editor` (último, por modo híbrido).

---

## 9. Retomada automática da escuta

### Comportamento atual

- Reinício em `onStatus` `done` / `notListening` e em `onError` (timeout).
- Guardas: escuta contínua ativa, não manual, não executando comando, não gravando (editor).

### Problemas

- Delays **inconsistentes** (700 ms vs 2 s).
- Corrida: reinício dispara enquanto navegação ainda não terminou.
- Home retoma após `pop`; filha também iniciou escuta no `initState` → **dupla escuta** possível.

### Correções priorizadas (Fase 1–2)

1. Coordenador: flag `navigationSuspended` durante `push`/`pop`.
2. `RouteAware` ou callback `onPageVisible` para **uma** escuta por rota visível.
3. Backoff único: `300 ms → 700 ms → 2 s` com teto.
4. Teste manual: Home → Projetos → voltar → verificar um único `listening`.

---

## 10. Navegação por voz e contexto

### O que funciona

- `CommandService` + comandos contextuais por tela.
- Home concentra navegação global (`abrir dashboard`, etc.) com parada de escuta antes do `push`.
- Telas filhas tratam subset local (`voltar`, ações da entidade).

### O que falta

- **Registro central de contexto** (rota atual, projeto aberto, gravação selecionada) para IA e comandos ambíguos (“abrir projeto X”).
- **Retomada previsível** ao voltar (hoje depende de cada page + Home).
- **VoicePage** legada — decidir: deprecar ou virar laboratório de debug.

### Evolução

`VoiceNavigationContext`:

```dart
class VoiceNavigationContext {
  final String routeId;
  final int? projetoId;
  final int? gravacaoId;
  final bool editorRecording;
}
```

Passado ao `VoiceCommandController.interpret` na Fase 3 para enriquecer Gemini sem quebrar parser local.

---

## 11. Experiência hands-free

| Recurso | Estado | Próximo passo |
|---------|--------|----------------|
| Escuta contínua fora do editor | Implementado | Centralizar reinício |
| Comandos sem tocar na Home | Implementado | Reduzir dupla escuta |
| Gravar sem tocar | Parcial — início por voz **antes** de gravar; durante gravar só manual | PTT ou janela em pausa |
| Confirmar exclusão por voz | Implementado nas telas que tratam `confirmarAcao` | Testes manuais |
| Feedback sonoro | Click/haptic (`VoiceFeedbackService`) | TTS opcional futuro |
| Status visual | `VoiceStatusBar` parcial | Mapear `VoiceSessionPhase` |
| Permissão negada | Básico (`VoicePermissionService`) | Fluxo “abrir configurações” + modo manual claro |

---

## 12. Uso no TCC (monografia)

### Seções sugeridas

1. **Arquitetura híbrida voz/áudio** — diagrama camadas (este doc §2).
2. **Modo estúdio (editor)** — trade-off microfone Android (§3–4).
3. **NLU em dois níveis** — local + Gemini (já implementado).
4. **Comandos contextuais** — tabela rota × comandos aceitos.
5. **Limitações** — sem wake word v1; sem voz durante gravação ativa.
6. **Evolução futura** — coordenador, wake word, insights dashboard (§5, §15 do AGENTS).

### Artefatos

- Diagrama de estados (`VoiceSessionPhase`).
- Casos de teste manuais Android (gravar + navegar + escuta contínua).
- Referência aos 26 testes automatizados (parser/IA/models).

---

## 13. Roadmap técnico resumido

```text
Fase 1 (estabilizar)     — singleton SpeechService, dispose/route, delays unificados, testes manuais
Fase 2 (deduplicar)      — VoiceListeningMixin + dispatcher por tela
Fase 3 (coordenador)     — VoiceSessionPhase + VoiceSessionCoordinator
Fase 4 (extensão)        — VoiceWakeWordEngine interface + implementação opcional
Fase 5 (TCC)             — DER atualizado, casos de teste, manual do usuário
```

Cada fase: `flutter analyze` + `flutter test` + atualizar este arquivo e `AGENTS.md`.

---

## 14. Registro de decisões (ADR)

| ID | Decisão | Data |
|----|---------|------|
| ADR-001 | Não reescrever arquitetura de voz; evoluir sobre `VoiceCommandController` | 2026-05-18 |
| ADR-002 | Manter modo híbrido no editor (STT off durante `record`) | 2026-05-18 |
| ADR-003 | Wake word apenas como camada futura via interface plugável | 2026-05-18 |
| ADR-004 | Priorizar singleton/coordenador antes de novo plugin STT | 2026-05-18 |
| ADR-005 | Migração de páginas para handler compartilhado incremental, não big-bang | 2026-05-18 |
| ADR-006 | Fase 1: `SpeechService.instance` + `VoiceListeningCoordinator` + `VoiceRouteObserver` | 2026-05-18 |
| ADR-007 | Fase 2: mixin + dispatcher; handlers por mapa ou `onFallback` | 2026-05-18 |
