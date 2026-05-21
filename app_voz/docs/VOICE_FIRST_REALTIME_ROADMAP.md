# Voice-First Realtime Roadmap And Risk Register

Data: 2026-05-20
Escopo: gargalos restantes, proximas etapas arquiteturais, estado hands-free e bloqueios antes de wake word.

## 1. Estado atual do objetivo Voice-First

O app ja e voice-first em partes importantes, mas ainda nao e 100% hands-free.

### O que ja e hands-free

- STT continuo pode ser ativado por configuracao.
- Home e telas contextuais conseguem receber comandos sem fluxo manual quando a escuta esta ativa.
- Parser local interpreta comandos deterministas.
- IA/Gemini atua como fallback para linguagem natural.
- Comandos globais de configuracao podem ativar/desativar voz, feedback, tema e escuta continua.
- O editor pode iniciar gravacao por voz antes de o microfone ser reservado ao recorder.
- A parada por silencio permite encerrar gravacao sem tocar na tela em um caso especifico.
- Playback participa da sessao global, reduzindo disputa com STT.
- Recovery tenta retomar escuta em falhas simples.

### O que ainda depende de UI ou fluxo manual

- Durante gravacao real, STT fica desligado porque o microfone esta reservado ao `record`.
- Comandos como "pausar", "retomar" e "encerrar" durante captura ativa ainda nao sao garantidos por voz.
- Confirmacoes sensiveis ainda dependem de implementacao por tela.
- O editor ainda interpreta comandos localmente em vez de registrar handlers em um core global.
- Algumas retomadas ainda dependem de lifecycle da pagina.
- Feedback de estado ainda e visual; nao ha TTS operacional.
- Nao existe wake word offline.
- Nao existe operacao robusta em background.

### O que falta para 100% hands-free

- wake-word offline ou estrategia nativa equivalente;
- audio focus Android real;
- orquestrador event-driven independente de pagina;
- memoria contextual da rota/entidade atual;
- camada conversacional capaz de dialogar, confirmar e resolver ambiguidade;
- politica segura para comandos durante gravacao;
- recovery global em foreground/background;
- diagnostico visual e persistente;
- testes manuais e automatizados de concorrencia realtime.

## 2. Gargalos restantes

### 2.1 Acoplamento restante no `EditorPage`

Apesar da extracao para `RecordingRealtimeCoordinator`, o editor ainda:

- interpreta comandos diretamente;
- chama `VoiceCommandController`;
- registra comandos de voz;
- registra historico;
- finaliza gravacao via callback;
- gera nome unico;
- conhece `RecordingManagementService`;
- manipula lista local de faixas;
- chama `_retomarEscutaContinuaAposModoGravacao`.

Risco: a pagina ainda tem responsabilidade de aplicacao e persistencia. Rebuilds e lifecycle ainda podem influenciar partes do fluxo.

Proxima extracao recomendada:

```text
EditorPage
  -> EditorController / EditorViewModel
    -> RecordingUseCase
      -> RecordingRealtimeCoordinator
      -> RecordingManagementService
      -> HistoricoRepository
```

### 2.2 Duplicidade entre `VoiceSessionState` e `VoiceStateMachine`

Problema: existe um estado canonico operacional e um estado local de UI. Algumas chamadas fazem transicoes nos dois.

Risco:

- divergencia entre UI e engine;
- `force: true` mascarando transicoes invalidas;
- estados presos se pagina nao sincronizar corretamente.

Proxima etapa:

- criar `VoiceSessionSnapshotView` derivado de `VoiceStateSnapshot`;
- migrar widgets para observar snapshot central;
- reduzir `VoiceSessionState` a adapter temporario ou remover.

### 2.3 `VoiceListeningCoordinator` ainda existe

Problema: ele e uma fachada, mas seu nome sugere autoridade.

Risco:

- novos codigos podem usa-lo achando que e o core;
- duplicidade conceitual com `VoiceSessionManager`;
- APIs antigas como `scheduleContinuousRestart` mantem linguagem de "restart", nao de "recovery".

Proxima etapa:

- marcar como deprecated em comentario;
- migrar chamadas remanescentes para `VoiceSessionManager`;
- manter somente se necessario para testes antigos.

### 2.4 Recovery ainda e local demais

Problema: o recovery depende de callbacks fornecidos por paginas/mixins.

Risco:

- pagina desmontada cancela recovery;
- pagina errada pode recuperar escuta depois de navegacao;
- falta politica global de rota visivel.

Proxima etapa:

- criar `VoiceRuntimeRegistry`;
- registrar owner ativo por rota;
- centralizar `onForeground`, `onRouteVisible`, `onRouteHidden`;
- recovery chama o handler ativo, nao uma closure solta da pagina antiga.

### 2.5 Audio focus ainda e de aplicacao, nao nativo

Problema: o manager controla regras internas, mas nao conversa com Android Audio Focus.

Risco:

- outro app pode capturar audio;
- interrupcoes de chamada/notificacao podem quebrar sessao;
- Bluetooth/headset pode mudar estado sem evento tratado;
- playback e record ainda dependem do comportamento dos plugins.

Proxima etapa:

- estudar camada nativa Android/Kotlin;
- criar adapter `AudioFocusService`;
- eventos: gain, loss, transient loss, ducking, route changed;
- conectar esses eventos ao `VoiceSessionManager`.

### 2.6 Observabilidade ainda insuficiente

Problema: `VoiceDiagnostics` existe, mas so em memoria/debugPrint.

Risco:

- dificil diagnosticar Android real;
- falhas intermitentes de microfone ficam invisiveis;
- sem timeline para comparar STT/record/playback.

Proxima etapa:

- criar tela interna `VoiceDiagnosticsPage`;
- exportar eventos recentes;
- incluir owner, state, reason, timestamp e metadata;
- opcionalmente persistir ultimos eventos em SQLite ou arquivo local.

### 2.7 Testes de concorrencia ainda limitados

Problema: existem testes de state/session foundation, mas falta cobertura do editor realtime.

Risco:

- regressao em stop automatico;
- loop de recovery;
- dupla escuta apos rota;
- estado preso em `recording` ou `processing`.

Proxima etapa:

- fake de `AudioRecordingService`;
- fake de `AudioPlayerService`;
- testes com `fake_async` para timer de silencio;
- testes de generation/recovery;
- testes de dispose durante operations.

## 3. Roadmap tecnico recomendado

### Fase 0: estabilizar workspace atual

Objetivo: transformar o estado experimental atual em baseline confiavel.

Entregas:

- resolver travamento de `dart format`/`flutter analyze`;
- formatar arquivos novos;
- rodar analyze/test;
- corrigir qualquer erro de compilacao;
- revisar generated/local files;
- commit organizado da arquitetura foundation;
- teste manual Android basico.

Gate de saida:

- `dart format` ok;
- `flutter analyze` ok;
- testes de coordination ok;
- app compila;
- sem arquivos gerados irrelevantes no commit.

### Fase 1: concluir autoridade unica do manager

Objetivo: remover caminhos restantes que ainda sugerem controle distribuido.

Entregas:

- migrar uso remanescente do `VoiceListeningCoordinator`;
- reduzir `ContextualVoiceListeningMixin` para usar somente `VoiceSessionManager`;
- criar API clara: `requestListening`, `suspendListening`, `requestPlayback`, `requestRecording`;
- separar comandos de UI de operacoes de audio.

Gate de saida:

- nenhuma pagina chama `SpeechService` diretamente;
- nenhum controller de pagina agenda recovery proprio;
- todos os starts/stops de STT passam pelo manager.

### Fase 2: event-driven architecture

Objetivo: trocar callbacks soltos por eventos de runtime.

Proposta:

```text
VoiceRuntimeEventBus
  -> VoiceIntentRequested
  -> VoiceStateChanged
  -> SpeechResultReceived
  -> CommandInterpreted
  -> AudioOwnershipChanged
  -> RecordingStarted
  -> RecordingPaused
  -> RecordingStopped
  -> PlaybackStarted
  -> PlaybackStopped
  -> RecoveryScheduled
  -> RecoveryFailed
```

Beneficios:

- UI observa eventos e snapshots;
- recovery nao depende de closures antigas;
- testes conseguem simular eventos;
- diagnostico fica natural;
- facilita futura wake word.

Trade-off:

- aumenta infraestrutura;
- exige disciplina para nao virar global state sem contrato;
- precisa tipagem forte e lifecycle claro.

### Fase 3: `VoiceRuntimeEngine`

Objetivo: criar um core operacional acima do manager.

Responsabilidades:

- manter owner/rota/contexto ativo;
- conectar session manager, command controller, dispatcher e diagnostics;
- receber eventos de lifecycle;
- coordenar recovery;
- expor stream/snapshot unico para UI;
- permitir plugar wake word no futuro.

Forma alvo:

```text
VoiceRuntimeEngine
  - VoiceSessionManager
  - VoiceCommandController
  - VoiceRuntimeEventBus
  - VoiceNavigationContext
  - VoiceDiagnostics
```

### Fase 4: contextual memory

Objetivo: comandos naturais precisam saber onde o usuario esta e qual entidade esta ativa.

Modelo inicial:

```text
VoiceContextSnapshot
  routeId
  visiblePage
  usuarioId
  projetoId
  gravacaoId
  editorState
  recordingState
  pendingConfirmation
```

Uso:

- enriquecer `VoiceCommandController.interpret`;
- resolver comandos como "toque essa", "renomeie para X", "voltar para o projeto";
- permitir confirmacoes conversacionais.

### Fase 5: conversational layer

Objetivo: deixar de ser apenas comando -> acao e virar interacao assistiva.

Recursos:

- perguntas de confirmacao;
- desambiguacao;
- memoria curta da conversa;
- respostas estruturadas;
- TTS opcional;
- politicas de seguranca para exclusao/sobrescrita.

Regra: manter `CommandService` local como fallback deterministico.

### Fase 6: audio focus Android

Objetivo: tornar o core consciente do sistema operacional.

Entregas:

- adapter nativo Android;
- eventos de audio focus;
- eventos de route/device;
- politica para Bluetooth/headset;
- interrupcao por chamada;
- reconexao/recovery apos interrupcao.

### Fase 7: wake-word offline

Objetivo: ativacao hands-free real sem depender de STT continuo.

Nao implementar antes dos gates abaixo.

Interface alvo:

```dart
abstract class WakeWordEngine {
  Future<void> start({required void Function() onWake});
  Future<void> stop();
  bool get isRunning;
}
```

Politica:

- wake word roda somente quando `VoiceState.idle` ou estado equivalente permitir;
- wake word para durante `recording`;
- wake word para durante playback se houver risco de eco;
- onWake abre janela STT curta via `VoiceSessionManager`;
- se usuario nao fala, retorna a wake word;
- se comando entra, processa e volta ao estado anterior.

## 4. Pendencias criticas antes de wake-word

Wake-word offline nao deve ser implementado enquanto estes itens nao forem resolvidos:

1. `VoiceSessionManager` precisa ser a unica autoridade de STT em todo o app.
2. `VoiceListeningCoordinator` deve ser removido ou explicitamente deprecated.
3. Recovery deve ser global e independente de closures de pagina desmontada.
4. State machine deve ser fonte unica para UI de voz.
5. Editor deve mover persistencia/historico para controller/use case.
6. Android real deve validar:
   - STT continuo em foreground;
   - troca de rotas sem dupla escuta;
   - gravacao sem conflito;
   - parada por silencio;
   - retomada apos gravacao;
   - playback sem eco/concorrencia;
   - permissao negada;
   - app em resume.
7. Audio focus precisa ao menos de desenho tecnico aprovado.
8. Diagnostics precisa de visualizacao minima para depurar campo.
9. Testes automatizados precisam cobrir state machine, manager, coordinator e timer de silencio.

## 5. Riscos realtime atuais

| Risco | Severidade | Mitigacao atual | Mitigacao recomendada |
| --- | --- | --- | --- |
| STT e recorder competirem pelo microfone | Alta | `enterRecordingMode` cancela STT | Validar Android e adicionar audio focus |
| Recovery antigo reiniciar pagina errada | Alta | generation invalida callbacks antigos | Runtime registry por rota |
| UI divergir da state machine | Media | transicoes espelhadas | Snapshot unico central |
| Dispose encerrar estado indevido | Media | ownership por ownerId | testes de dispose e owner mismatch |
| Playback gerar eco em STT | Media | playback cancela STT | audio focus + politica de duck/stop |
| Stop automatico falhar silenciosamente | Media | diagnostics de erro | testes fake_async e UI diagnostica |
| Ferramentas Dart travarem localmente | Media | registrado como bloqueio | corrigir ambiente antes de commit |
| Mojibake em textos antigos | Baixa/Media | evitar editar sem necessidade | normalizar encoding em etapa propria |

## 6. Padroes que devem ser seguidos

- Nenhuma pagina nova deve chamar `SpeechService` diretamente.
- Nenhuma pagina deve criar timer de recovery ou silencio se um coordenador puder assumir.
- Toda disputa de audio deve passar pelo `VoiceSessionManager`.
- Todo estado operacional deve emitir diagnostico.
- UI deve observar estado e emitir intencao.
- Persistencia deve ficar em service/use case/repository, nao em core realtime.
- Wake word deve ser pluggable e desligavel.
- Controles manuais continuam obrigatorios como fallback.

## 7. Ordem recomendada para proximas tarefas

1. Corrigir/validar ambiente Dart/Flutter.
2. Rodar format/analyze/test no estado atual.
3. Corrigir possiveis erros introduzidos pela extracao do editor.
4. Criar testes para `RecordingRealtimeCoordinator`.
5. Extrair finalizacao/historico do `EditorPage`.
6. Migrar `ContextualVoiceListeningMixin` para remover dependencia direta do coordinator facade.
7. Criar diagnostics page interna.
8. Criar `VoiceRuntimeEventBus`.
9. Criar `VoiceRuntimeEngine`.
10. Planejar audio focus Android.
11. Somente entao desenhar implementacao wake-word.

