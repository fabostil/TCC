# Touchless — Assistente Musical Voice-First

Aplicativo Android desenvolvido em Flutter/Dart como projeto de TCC para apoiar músicos independentes durante a produção musical. Permite capturar, organizar, reproduzir e acompanhar ideias musicais por **comandos de voz** como experiência principal, com controles por toque como fallback obrigatório.

> **Princípio do produto:** voice-first, não voice-only. Se a voz falhar, o toque continua funcionando.

---

## Funcionalidades

- Autenticação local (e-mail + senha com PBKDF2-HMAC-SHA256) e Google Sign-In
- Criação e organização de projetos musicais
- Gravação real de áudio (`.m4a`) com pausa, retomada e encerramento
- Parada automática por silêncio configurável
- Listagem, reprodução, renomeação e exclusão de gravações
- Histórico persistente de ações
- Dashboard com métricas reais
- Configurações persistidas (tema, escuta contínua, feedback sonoro, tempo de silêncio)
- Comandos de voz contextuais por tela (~45 intents)
- Escuta contínua com reinício automático
- Fallback para Gemini (NLU natural quando o parser local não reconhece)
- Modo híbrido no Editor: STT pausado enquanto o microfone está em uso para gravação
- Comandos personalizados salvos no banco local

---

## Arquitetura

### Camadas

```
Presentation / Page
  → Controller / ViewModel
      → Service / UseCase
          → Repository
              → SQLite (sqflite)
```

### Pipeline de voz

```
SpeechService (singleton STT)
  → VoiceCommandController
      → CommandService          (parser local, offline, sem custo)
      → CustomCommandService    (comandos personalizados do usuário)
      → AiCommandService        (Gemini — fallback quando local retorna desconhecido)
  → VoiceCommandDispatcher      (contexto por tela)
  → Página executa ação
  → Repositories persistem comando / histórico / dados
```

### Modo híbrido do Editor

Durante a gravação, o STT é pausado para evitar conflito de microfone no Android:

```
Modo normal      → escuta contínua ativa
Modo gravação    → microfone reservado para áudio
                 → STT pausado
                 → controles manuais em destaque
                 → escuta retoma ao finalizar (se configurada)
```

### Coordenação de escuta

| Artefato | Responsabilidade |
|----------|-----------------|
| `SpeechService` | Singleton STT |
| `VoiceListeningCoordinator` | Dono único de start/stop/cancel do STT |
| `VoiceRouteObserver` | Cancela escuta ao empilhar rotas |
| `ContextualVoiceListeningMixin` | Mixin compartilhado pelas páginas |
| `VoiceCommandDispatcher` | Despacha comandos contextuais por mapa |
| `VoicePageOwners` | IDs de owner por tela |

---

## Stack

| Tecnologia | Uso |
|-----------|-----|
| Flutter / Dart | Framework principal |
| Android | Plataforma alvo |
| `sqflite` | Banco local SQLite |
| `speech_to_text` | STT contínuo |
| `record` | Captura de áudio (`.m4a`) |
| `just_audio` | Reprodução de áudio |
| `permission_handler` | Permissão de microfone |
| `google_sign_in` | Autenticação Google |
| `flutter_foreground_task` | Serviço em foreground Android |
| `crypto` | PBKDF2-HMAC-SHA256 para senhas |
| `path_provider` / `path` | Caminhos de arquivo |
| Gemini API (opcional) | NLU de linguagem natural como fallback |

---

## Banco Local

Arquivo: `assistente_musical.db` (SQLite)

| Tabela | Conteúdo |
|--------|----------|
| `usuario` | Cadastros locais e vínculos Google |
| `projeto` | Projetos musicais |
| `gravacao` | Metadados e caminho dos arquivos de áudio |
| `comando_voz` | Histórico de comandos reconhecidos |
| `historico_acao` | Log de ações do usuário |
| `configuracao_app` | Configurações persistidas por usuário |
| `comando_personalizado` | Comandos definidos pelo usuário |

---

## Como Rodar

### Pré-requisitos

- Flutter SDK (Dart SDK `^3.11.1`)
- Android SDK / dispositivo ou emulador Android

### Sem Gemini

```powershell
flutter pub get
flutter run
```

### Com Gemini (NLU natural como fallback)

```powershell
flutter run --dart-define=GEMINI_API_KEY=SUA_CHAVE
```

### Modelo Gemini customizado (opcional)

```powershell
flutter run --dart-define=GEMINI_API_KEY=SUA_CHAVE --dart-define=GEMINI_MODEL=gemini-1.5-flash
```

### Em dispositivo físico

```powershell
flutter devices
flutter run -d <DEVICE_ID>
```

### Gerar APK debug

```powershell
flutter build apk --debug
```

---

## Validação

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

Estado verificado:

- `flutter analyze`: sem issues
- `flutter test`: 34+ testes passando
- `flutter build apk --debug`: gera APK com sucesso
- Checklist manual Android: [`docs/ANDROID_MANUAL_TEST_CHECKLIST.md`](docs/ANDROID_MANUAL_TEST_CHECKLIST.md)

### Fallback (se o wrapper travar)

```powershell
C:\Users\aleli\flutter\bin\cache\dart-sdk\bin\dart.exe C:\Users\aleli\flutter\bin\cache\flutter_tools.snapshot analyze
C:\Users\aleli\flutter\bin\cache\dart-sdk\bin\dart.exe C:\Users\aleli\flutter\bin\cache\flutter_tools.snapshot test --reporter compact
```

---

## Comandos de Voz — Exemplos

### Navegação

```
abrir dashboard
abrir projetos
abrir gravacoes
abrir configuracoes
abrir historico
voltar
voltar para home
```

### Projetos

```
novo projeto
nome do projeto guitarra rock
descricao do projeto riff para o verso
criar projeto
cancelar projeto
abrir projeto guitarra rock
renomear projeto guitarra rock para blues
```

### Gravações

```
reproduzir gravacao ideia inicial
parar audio
abrir detalhes da gravacao ideia inicial
renomear gravacao ideia inicial para riff verso
excluir gravacao riff verso
confirmar exclusao
cancelar exclusao
```

### Configurações

```
ativar escuta continua
desativar escuta continua
ativar feedback sonoro
desativar feedback sonoro
ativar parada por silencio
desativar parada por silencio
tempo de silencio 8 segundos
ativar tema escuro
```

### Editor

```
iniciar gravacao
pausar gravacao
retomar gravacao
encerrar gravacao
reproduzir
parar audio
criar marcador
```

---

## Segurança

- Senhas locais: PBKDF2-HMAC-SHA256 com salt individual por usuário
- Migração progressiva de senhas legadas SHA-256 no primeiro login correto
- API keys não devem ser expostas em logs, prints, UI ou documentos públicos
- Logout centralizado no `AuthSessionService`
- Migrations do SQLite usam whitelist de colunas e definições permitidas

### Limitações conhecidas

- SQLite local sem criptografia em repouso (ver [`docs/security/sqlite_local_storage.md`](docs/security/sqlite_local_storage.md))
- Validação server-side do `idToken` Google não implementada
- SHA-1 de release deve ser cadastrado no Google Cloud antes de gerar APK release

---

## Testes

A estratégia prioriza determinismo e isolamento:

- Fakes manuais em vez de pacotes de mocking
- Banco isolado com `sqflite_common_ffi` nos testes de repositórios
- Nenhum teste abre microfone, player, STT, TTS ou serviço real
- Clientes injetáveis para Google, permissão, gravador e player

### Cobertura atual

| Grupo | Arquivo(s) |
|-------|-----------|
| Parser de voz | `test/features/voices/` |
| `ComandoVozRepository` | `test/repositories/comando_voz_repository_test.dart` |
| `HistoricoRepository` | `test/repositories/historico_repository_test.dart` |
| `UsuarioRepository` | `test/repositories/usuario_repository_test.dart` |
| Migrations SQLite | `test/database/app_database_migration_test.dart` |
| `GoogleAuthService` | `test/features/voices/services/` |
| `VoicePermissionService` | `test/features/voices/services/` |
| `AudioRecordingService` / `AudioPlayerService` | `test/features/editor/` |
| `LoginPage` / `CadastroPage` / `HomePage` | `test/features/voices/pages/`, `test/features/home/` |

---

## Pendências Conhecidas

- Teste manual completo em Android físico (gravação + escuta contínua + navegação)
- Preencher o checklist manual Android com evidências
- Centralizar escuta de voz — evitar múltiplas instâncias de `SpeechService` (ver `docs/VOICE_ARCHITECTURE.md`)
- Melhorar fluxo de permissão negada permanentemente
- Feedback TTS opcional (hoje: click/haptic)
- Insights inteligentes no dashboard (atualmente placeholder)
- Decidir destino da `VoicePage` legada
- Documentação acadêmica final do TCC

---

## Documentação Técnica

| Documento | Conteúdo |
|-----------|---------|
| [`docs/VOICE_ARCHITECTURE.md`](docs/VOICE_ARCHITECTURE.md) | Arquitetura de voz, fases de evolução e ADRs |
| [`docs/ANDROID_MANUAL_TEST_CHECKLIST.md`](docs/ANDROID_MANUAL_TEST_CHECKLIST.md) | Checklist de teste físico em Android |
| [`docs/validacao_final_tcc.md`](docs/validacao_final_tcc.md) | Validação técnica final e evidências |
| [`docs/security/sqlite_local_storage.md`](docs/security/sqlite_local_storage.md) | Limitações de segurança do banco local |
| [`AGENTS.md`](AGENTS.md) | Guia de trabalho para agentes de IA na sprint final |

---

## Observações de Git

Arquivos iOS gerados podem aparecer modificados localmente:

- `ios/Runner/GeneratedPluginRegistrant.h`
- `ios/Runner/GeneratedPluginRegistrant.m`

Não devem ser commitados sem revisão explícita.
