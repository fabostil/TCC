# Assistente Musical Voice-First

Aplicativo Flutter para Android criado como projeto academico/TCC para apoiar musicos independentes na captura, organizacao, reproducao e acompanhamento de ideias musicais usando comandos de voz como experiencia principal e controles manuais como fallback.

## Objetivo

Reduzir interrupcoes no fluxo criativo. O usuario pode navegar, criar projetos, gravar ideias, organizar gravacoes e consultar historico/dashboard por voz quando a escuta continua esta ativa.

## Estado Atual

O app possui:

- cadastro e login local;
- projetos musicais;
- gravacao real de audio;
- pausa, retomada e encerramento;
- parada automatica por silencio;
- listagem, reproducao, renomeacao e exclusao de gravacoes;
- historico persistente;
- dashboard com metricas reais;
- configuracoes persistidas;
- escuta continua;
- comandos contextuais por tela;
- fallback com Gemini para linguagem natural;
- modo hibrido no Editor para evitar conflito de microfone durante gravacao.

## Arquitetura De Voz

```text
SpeechService
  -> VoiceCommandController
      -> CommandService local
      -> AiCommandService/Gemini se local nao entender
  -> Tela executa acao contextual
  -> Repositories persistem comando/historico/dados
```

`CommandService` e a primeira camada. Ele e local, rapido e sem custo.

`AiCommandService` usa Gemini apenas como fallback quando o parser local retorna `desconhecido`.

## Como Rodar

Sem Gemini:

```powershell
flutter run
```

Com Gemini:

```powershell
flutter run --dart-define=GEMINI_API_KEY=SUA_CHAVE
```

Modelo Gemini opcional:

```powershell
flutter run --dart-define=GEMINI_API_KEY=SUA_CHAVE --dart-define=GEMINI_MODEL=gemini-1.5-flash
```

## Validacao

```powershell
flutter analyze
flutter test
```

Estado atual verificado:

- `flutter analyze`: sem issues.
- `flutter test`: 17 testes passando.

## Comandos Exemplos

Navegacao:

```text
abrir dashboard
abrir projetos
abrir gravacoes
abrir configuracoes
abrir historico
voltar
voltar para home
```

Projetos:

```text
novo projeto
eu quero que voce coloque o nome abacate
descricao do projeto ideia simples para tocar na rua
criar projeto
cancelar projeto
abrir projeto abacate
renomear projeto abacate para alface
```

Gravacoes:

```text
reproduzir gravacao teste
parar audio
renomear gravacao teste para ideia inicial
excluir gravacao ideia inicial
confirmar exclusao
cancelar exclusao
```

Configuracoes:

```text
ativar escuta continua
desativar escuta continua
ativar feedback sonoro
desativar feedback sonoro
ativar parada por silencio
desativar parada por silencio
tempo de silencio 8 segundos
```

Editor:

```text
iniciar gravacao
pausar gravacao
retomar gravacao
encerrar gravacao
reproduzir
parar audio
criar marcador
```

## Modo Hibrido Do Editor

Durante a gravacao, o app pausa a escuta por voz e dedica o microfone a captura musical. Isso evita conflito real do Android entre `speech_to_text` e `record`.

Fluxo:

```text
Modo normal
  -> escuta continua ativa

Modo gravacao
  -> microfone reservado para audio
  -> escuta por voz pausada
  -> controles manuais grandes
  -> escuta volta ao finalizar se configurada
```

## Banco Local

SQLite: `assistente_musical.db`

Tabelas:

- `usuario`
- `projeto`
- `gravacao`
- `comando_voz`
- `historico_acao`
- `configuracao_app`

## Pendencias Principais

- Teste manual completo em Android real (gravacao + escuta continua + navegacao).
- Centralizar escuta de voz (evitar multiplas instancias `SpeechService`) — ver `docs/VOICE_ARCHITECTURE.md`.
- Melhorar fluxo de permissao negada.
- Feedback sonoro/TTS opcional (hoje: click/haptic).
- Corrigir mojibake remanescente.
- Decidir destino da `VoicePage` legada.
- Insights inteligentes no dashboard (placeholder).
- Atualizar documentacao academica final do TCC.

## Arquitetura De Voz (evolucao)

Plano incremental sem reescrever a base: `docs/VOICE_ARCHITECTURE.md`

## Observacao De Git

Arquivos iOS gerados podem aparecer modificados localmente:

- `ios/Runner/GeneratedPluginRegistrant.h`
- `ios/Runner/GeneratedPluginRegistrant.m`

Eles nao devem ser commitados sem revisao explicita.
