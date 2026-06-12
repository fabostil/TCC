# Auditoria do TCC Overleaf contra o código real

## 1. Resumo executivo

Classificação: **parcialmente alinhado**.

O TCC exportado do Overleaf possui estrutura acadêmica ampla e cobre os elementos exigidos pelos orientadores: introdução, fundamentação, análise, requisitos, casos de uso, diagramas, protótipo, modelagem de dados, testes, resultados, conclusão e manual técnico. Porém, a documentação não está totalmente aderente ao código real atual. As principais divergências estão no banco de dados, nos requisitos, nos diagramas em PNG sem fonte PlantUML no export, nos fluxos de autenticação Google, projetos, comandos personalizados, detalhes de gravação, segurança PBKDF2 e validação física Android ainda em andamento.

O maior risco é o documento afirmar como concluídos alguns testes físicos ou estruturas de dados que não correspondem ao app real, enquanto deixa de documentar funcionalidades implementadas e testadas.

## 2. Pontos já fortes

- O arquivo principal LaTeX foi identificado em `documentacao/tcc/TCC/main.tex`.
- O TCC contém capítulos e seções esperados para a entrega: introdução, fundamentação teórica, análise do sistema atual, levantamento de requisitos, metodologia, diagramas, protótipo, modelagem de dados, relatório de testes, resultados, conclusão e manual técnico.
- Os requisitos RF01 a RF16 cobrem o núcleo original do projeto: cadastro, login, voz, gravação, reprodução, histórico e dashboard.
- Há especificação textual para cada caso de uso RF01 a RF16, com ator, descrição, pré-condição, pós-condição, fluxo principal, fluxo alternativo e fluxo de erro.
- O TCC já reconhece uma arquitetura voice-first experimental e diferencia o fluxo legado do modo experimental por flag.
- O manual técnico já menciona Flutter, Android SDK, `flutter pub get`, `flutter run`, permissão de microfone e `USE_STREAM_FIRST_AUDIO=true`.
- O relatório de validação já possui seção específica para testes funcionais e arquitetura voice-first experimental.
- O documento inclui imagens de telas reais ou esperadas do protótipo: login, cadastro, inicial, gravações, histórico, dashboard, configurações e resultado de gravação.

## 3. Divergências críticas

### 3.1 Script SQL e DER não refletem o banco real

- Seção/arquivo: `documentacao/tcc/TCC/main.tex`, seção "SCRIPT DE CRIAÇÃO DO BANCO DE DADOS"; imagem `der-assistente.png`.
- Problema: o script SQL documenta tabelas `arquivo_audio`, `feedback`, `dashboard_indicador` e `historico_gravacao`, mas o código real usa `usuario`, `projeto`, `gravacao`, `comando_voz`, `comando_personalizado`, `historico_acao` e `configuracao_app`. O banco real está em `version: 9`, não em v8.
- Impacto: banca pode questionar a aderência entre projeto lógico e projeto físico, especialmente porque o critério dos orientadores exige script do banco e DER coerentes com a implementação.
- Recomendação: atualizar DER e script SQL a partir de `lib/database/app_database.dart` e `lib/database/tables/*.dart`, incluindo migrations v2 a v9, índices e chaves estrangeiras reais.

### 3.2 Teste físico Android aparece como aprovado, mas ainda não deve ser declarado concluído

- Seção/arquivo: `documentacao/tcc/TCC/main.tex`, "RESULTADOS OBTIDOS NOS TESTES" e "ROTEIRO DE VALIDAÇÃO DO FLUXO DO SISTEMA".
- Problema: o texto registra CT11 como execução em ambiente Android compatível aprovada. A instrução da etapa informa que o teste físico em aparelho Android está em andamento e não deve ser declarado concluído.
- Impacto: risco alto de inconsistência em arguição, pois diferencia validação automatizada/build de validação real em aparelho.
- Recomendação: na etapa posterior, separar evidência automatizada validada (`dart analyze`, `flutter test`, `flutter build apk --debug`, cobertura) de teste físico Android em andamento.

### 3.3 Requisitos não cobrem funcionalidades reais importantes

- Seção/arquivo: `documentacao/tcc/TCC/main.tex`, seção "REQUISITOS FUNCIONAIS".
- Problema: o app real possui projetos musicais, busca/filtro, comandos personalizados, configurações persistentes, tema escuro, Google Login, logout centralizado, tela de detalhes da gravação, metadados/status de arquivo, dashboard com insights locais, segurança PBKDF2 e módulos realtime/TTS/wake-word/Deepgram experimentais. Esses itens não aparecem ou aparecem só parcialmente nos RF/RNF.
- Impacto: a documentação subestima o produto real e prejudica a rastreabilidade entre requisitos, casos de uso, testes e implementação.
- Recomendação: adicionar ou reescrever requisitos para cobrir autenticação Google, gerenciamento de projetos, configurações, comandos personalizados, detalhes/metadados de gravação, segurança de senha, busca, logout e limitações offline/online.

### 3.4 Diagramas não podem ser auditados em PlantUML porque as fontes não foram encontradas

- Seção/arquivo: `documentacao/tcc/TCC/`.
- Problema: não foram encontrados arquivos `.puml` ou `.plantuml`; apenas imagens `.png` dos diagramas.
- Impacto: é possível auditar a presença dos diagramas, mas não a consistência interna de classes/métodos/mensagens no nível PlantUML. Se os orientadores pedirem fonte editável, haverá risco operacional.
- Recomendação: na etapa posterior, localizar os `.puml` originais fora do export ou recriar fontes a partir do código real, sem alterar a formatação ABNT/UTP.

### 3.5 Casos de uso sem sequência correspondente para todo o escopo

- Seção/arquivo: `documentacao/tcc/TCC/main.tex`, "ESPECIFICAÇÃO DOS CASOS DE USO" e "DIAGRAMA DE SEQUÊNCIA".
- Problema: há especificações RF01 a RF16, mas os diagramas de sequência citados são gerais: assistente virtual e criação/autenticação de usuário. Não há sequência específica para todos os casos relevantes, como projetos, configurações, comandos personalizados, detalhes de gravação, exclusão com confirmação e logout.
- Impacto: conforme a regra desta auditoria, especificação de caso de uso sem diagrama de sequência correspondente deve ser marcada como risco.
- Recomendação: atualizar o conjunto mínimo de sequências para cobrir os fluxos críticos ou deixar claro que o diagrama geral agrupa múltiplos casos.

## 4. Divergências por seção do TCC

| Arquivo .tex | Seção | Situação atual | Divergência encontrada | Ação recomendada | Prioridade |
|---|---|---|---|---|---|
| `main.tex` | Introdução | Tema e problema estão coerentes com o objetivo voice-first. | Precisa refletir melhor o estágio atual: app híbrido voice-first com Google Login, Gemini fallback e arquitetura experimental controlada. | Atualizar escopo sem mexer em normas/formatação. | Médio |
| `main.tex` | Fundamentação teórica | Cobre assistentes virtuais, voz, Flutter, SQLite, UML e arquitetura voice-first. | Pode faltar fundamentação curta para segurança local, autenticação Google, NLU com LLM e limitações de reconhecimento em Android. | Acrescentar apenas conteúdo técnico necessário. | Médio |
| `main.tex` | Análise do sistema atual | Contextualiza o problema do músico independente. | Não evidencia todos os fluxos reais atuais, como projetos, configurações persistentes, histórico de ações e escuta contextual. | Atualizar análise para o app real. | Médio |
| `main.tex` | Requisitos funcionais | RF01-RF16 cobrem o núcleo original. | Faltam RFs para projetos, comandos personalizados, Google Login, configurações, tema escuro, busca, detalhes de gravação, logout e gerenciamento de permissões. | Reestruturar ou adicionar RFs rastreáveis. | Alto |
| `main.tex` | Requisitos não funcionais | RNF01-RNF10 cobrem desempenho, usabilidade, Android, offline e segurança. | RNF10 diz garantir segurança, mas o SQLite local não tem criptografia em repouso; falta explicitar mitigação de API key, SHA-1 release e ausência de backend server-side para Google. | Ajustar RNFs para prometer o que o app realmente entrega e registrar riscos residuais. | Alto |
| `main.tex` | Metodologia | Justifica POO e desenvolvimento incremental. | Cita entidades planejadas como `arquivo de áudio`, `feedback` e `dashboard` como se fossem estruturas de banco, mas no código algumas são cálculos/serviços e não tabelas. | Alinhar metodologia aos modelos/repositories/services reais. | Médio |
| `main.tex` | Diagrama de caso de uso | Há imagem para caso de uso do assistente. | Sem fonte PlantUML encontrada; provável ausência de casos reais novos. | Atualizar caso de uso com projetos, configurações, Google, comandos personalizados e detalhes de gravação. | Alto |
| `main.tex` | Especificação dos casos de uso | RF01-RF16 têm especificações. | Fluxos alternativos como confirmação parcial por voz podem não existir como descritos; faltam fluxos de permissão negada, Google cancelado, microfone ocupado e falha de arquivo. | Revisar cada fluxo contra handlers reais. | Alto |
| `main.tex` | Diagrama de classes | Há imagem do diagrama de classes. | Sem fonte editável; provável defasagem frente a controllers, services, repositories, realtime, theme e auth. | Atualizar com classes reais principais, evitando excesso de detalhe experimental. | Alto |
| `main.tex` | Diagramas de sequência | Há diagrama geral do assistente e autenticação. | Não há sequência dedicada para muitos casos de uso especificados. Pode haver mensagens/classes não verificáveis por falta de PlantUML. | Criar sequências mínimas dos fluxos críticos. | Alto |
| `main.tex` | DER | Há imagem do DER. | DER textual fala em `arquivo_audio`, `feedback`, `dashboard`, mas o banco real usa outras tabelas e campos. | Atualizar DER a partir de `AppDatabase` v9. | Crítico |
| `main.tex` | Fluxo de navegação | Há imagem `fluxo-navegacao.png`. | Texto cita "tela do assistente virtual"; no app real não há `VoicePage` separada, e a voz é contextual em Home/Projetos/Gravações/Configurações/Detalhes, com fluxo próprio no Editor. | Atualizar navegação real. | Alto |
| `main.tex` | Protótipo do sistema | Contém telas principais. | Faltam telas de projetos, detalhes do projeto, editor, detalhes da gravação e possivelmente estados de permissão/voz. | Atualizar capturas em etapa posterior sem alterar layout ABNT. | Médio |
| `main.tex` | Modelagem de dados | Explica entidades. | Mistura entidades lógicas planejadas com tabelas inexistentes. Não menciona `configuracao_app`, `comando_personalizado`, campos PBKDF2 ou `projeto`. | Reescrever modelagem a partir das tabelas reais. | Crítico |
| `main.tex` | Relatório de testes | Contém plano e resultados. | Não registra os resultados atuais informados: 396 testes, coverage e build debug. Declara Android compatível como aprovado apesar do teste físico estar em andamento. | Atualizar evidências e separar testes automatizados de físicos. | Alto |
| `main.tex` | Demonstração de resultados | Cobre controle por voz e indicadores. | Deve mencionar dashboard com insights locais e limitações de comandos em gravação por conflito de microfone. | Atualizar resultados sem superprometer hands-free durante gravação. | Médio |
| `main.tex` | Conclusão | Encaminha evolução do protótipo. | Deve refletir riscos residuais e validações pendentes. | Ajustar conclusão com limitações reais. | Médio |
| `main.tex` | Manual técnico | Cobre instalação e uso básico. | Faltam APK debug, Google Login, SHA-1 debug/release, permissões detalhadas, funcionamento offline/parcial, comandos principais e problemas conhecidos. | Expandir manual técnico. | Alto |

## 5. Requisitos que precisam ajuste

### RF/RNF atuais que parecem desatualizados

- RF02: autenticação está descrita apenas por e-mail e senha. O app real também possui Google Login com vínculo local em SQLite.
- RF03: reconhecer comandos de voz está correto, mas deve explicitar parser local, comandos personalizados e fallback Gemini quando configurado.
- RF04 a RF07: controle por voz de gravação precisa respeitar o modo híbrido real do Editor, em que o STT é pausado durante a captura para evitar disputa de microfone.
- RF10: feedback visual/auditivo precisa distinguir SnackBars/status visual, click/haptic e TTS experimental. Não afirmar TTS como fluxo padrão se não for o comportamento produtivo.
- RF11: organizar por data ou nome está genérico. O app real tem busca/filtro e projetos, além de listagens por usuário/projeto.
- RF14: nomear gravação por comando de voz deve ser validado contra o fluxo real de renomeação por voz nas listas/detalhes. No Editor, durante gravação, o microfone fica reservado.
- RF16: dashboard agora possui métricas reais e insights locais, não apenas contadores básicos.
- RNF01: tempo inferior a 2 segundos vale para comandos simples locais; chamadas Gemini têm timeout de 2 segundos e dependem de rede.
- RNF06: funcionamento parcialmente offline deve dizer que parser local, banco e fluxos manuais funcionam offline, mas Gemini/Google/Deepgram dependem de rede/configuração.
- RNF10: segurança precisa ser reescrita para PBKDF2 com salt, mas com risco residual de SQLite sem criptografia em repouso.

### RF/RNF que precisam ser adicionados

- Gerenciar projetos musicais: criar, listar, buscar, abrir, renomear e excluir projetos.
- Associar gravações a projetos e visualizar detalhes de projeto.
- Buscar/filtrar gravações e projetos.
- Visualizar detalhes da gravação, incluindo status do arquivo, tamanho, formato e metadados.
- Autenticar ou cadastrar com Google Sign-In, com usuário local vinculado.
- Encerrar sessão com limpeza de contexto de voz/runtime.
- Configurar comandos de voz, escuta contínua, feedback sonoro, parada por silêncio, tempo de silêncio e tema escuro.
- Cadastrar e gerenciar comandos personalizados.
- Registrar comandos reconhecidos e não reconhecidos.
- Exibir status de voz e estado "IA pensando".
- Aplicar segurança de senha com PBKDF2-HMAC-SHA256, salt e migração de SHA-256 legado.
- Executar modo experimental realtime por flags, sem substituir o fluxo padrão.

### RF/RNF que precisam ser removidos ou reescritos

- Entidade/tabela `arquivo_audio` como tabela física: no app real os metadados ficam em `gravacao`.
- Entidade/tabela `feedback`: feedback existe como UI/serviço, mas não como tabela SQLite real.
- Entidade/tabela `dashboard_indicador`: dashboard calcula por repositories/services, não persiste tabela dedicada.
- `historico_gravacao`: o nome real é `historico_acao`.
- Qualquer requisito que implique reconhecimento de voz ativo durante gravação musical deve ser reescrito para respeitar o modo híbrido.

## 6. Casos de uso e especificações

Os casos de uso RF01 a RF16 cobrem parte do app real, principalmente o núcleo original. A cobertura é insuficiente para o estado atual porque faltam casos de uso de projetos, configurações, Google Login, comandos personalizados, busca, detalhes de gravação, logout, permissão negada e arquitetura experimental.

Há especificações suficientes em formato acadêmico para os 16 casos existentes, mas alguns fluxos alternativos parecem mais idealizados do que implementados. Exemplo: "comando reconhecido parcialmente solicita confirmação" deve ser conferido contra `CommandService`, `AiCommandService` e dispatchers reais. O fluxo real de confirmação existe claramente para exclusões/ações pendentes, mas não necessariamente para qualquer comando parcial.

Fluxos de erro que precisam aparecer:

- e-mail inválido, senha fraca e senha incorreta;
- Google Sign-In cancelado ou falho;
- microfone negado, permanentemente negado ou indisponível;
- microfone ocupado durante gravação;
- comando desconhecido sem Gemini configurado;
- limite/rate limit ou timeout da Gemini;
- arquivo de gravação ausente;
- tentativa de reproduzir/excluir/renomear item inexistente;
- logout com falha parcial;
- tentativa de usar recursos experimentais sem flag/configuração.

Risco específico: há especificações de caso de uso sem sequência correspondente individual. A recomendação é criar um conjunto reduzido de sequências para os fluxos críticos em vez de tentar uma sequência para cada RF.

## 7. Diagramas PlantUML/UML

Não foram encontrados arquivos `.puml` ou `.plantuml` em `documentacao/tcc/`. Foram encontrados apenas diagramas renderizados como imagens.

| Arquivo | Tipo de diagrama | Status | Divergência | Classes/métodos reais que deveriam aparecer | Prioridade |
|---|---|---|---|---|---|
| `diagrama-caso-uso-assistente.png` | Caso de uso | Presente como imagem | Provável defasagem por não cobrir projetos, configurações avançadas, Google Login, comandos personalizados e detalhes de gravação. | N/A para classes; incluir atores/casos reais. | Alto |
| `diagrama-caso-uso-editor-audio.png` | Caso de uso/editor | Presente como imagem, mas não referenciado no trecho principal encontrado. | Pode estar desconectado do `EditorPage` atual e do modo híbrido. | `EditorPage`, `RecordingRealtimeCoordinator`, `AudioRecordingService`, `AudioPlayerService`. | Médio |
| `diagrama-classes-assistente.png` | Classes | Presente como imagem | Precisa refletir controllers, services, repositories e models reais. | `Usuario`, `Projeto`, `Gravacao`, `ComandoVoz`, `ComandoPersonalizado`, `ConfiguracaoApp`, `HistoricoAcao`, `AuthService`, `GoogleAuthService`, `PasswordHashService`, `CommandService`, `AiCommandService`, `SpeechService`, `VoiceCommandController`, repositories. | Alto |
| `diagrama-classes-editor-audio.png` | Classes/editor | Presente como imagem, mas não referenciado no trecho principal encontrado. | Deve refletir a gravação legado `.m4a`, stream-first experimental `.wav` e coordenação realtime. | `EditorPage`, `AudioRecordingCapture`, `AudioRecordingService`, `StreamFirstAudioRecordingService`, `PcmWavFileWriter`, `RecordingRealtimeCoordinator`, `VoiceRealtimeEcosystem`. | Médio |
| `diagrama-sequencia-assistente.png` | Sequência | Presente como imagem | Diagrama geral não cobre todos os casos especificados e pode não refletir dispatchers/contextos atuais. | `SpeechService`, `VoiceCommandController`, `CommandService`, `AiCommandService`, `VoiceCommandDispatcher`, repositories. | Alto |
| `diagrama-sequencia-autenticacao.png` | Sequência/autenticação | Presente como imagem | Deve incluir PBKDF2, migração de senha legada e Google Sign-In se o texto de autenticação for atualizado. | `LoginPage`, `CadastroPage`, `AuthService`, `AuthValidationService`, `PasswordHashService`, `GoogleAuthService`, `UsuarioRepository`. | Alto |
| `diagrama-sequencia-editor-audio.png` | Sequência/editor | Presente como imagem, mas não referenciado no trecho principal encontrado. | Deve explicitar pausa do STT durante gravação e retomada pós-gravação. | `EditorPage`, `VoiceSessionManager`, `RecordingRealtimeCoordinator`, `AudioRecordingService`, `AudioPlayerService`. | Alto |
| `arquitetura-voice-first.png` | Arquitetura | Presente e citado | Conceito está alinhado, mas deve distinguir com precisão estável vs experimental. | `VoiceRuntimeEngine`, `AudioPipelineIsolate`, `AudioIsolateBridge`, `AdaptiveSilenceVad`, `WakeWordEngine`, `DeepgramStreamingAdapter`, `FlutterTtsEngine`, `VoiceForegroundService`. | Médio |
| `der-assistente.png` | DER | Presente como imagem | Crítico: entidades/tabelas textuais não batem com SQLite real v9. | Tabelas reais listadas na seção 8. | Crítico |
| `der-editor-audio.png` | DER/editor | Presente como imagem, mas não referenciado no trecho principal encontrado. | Validar se não duplica `arquivo_audio` inexistente. | `gravacao` com `formato_audio`, `tamanho_bytes`, `status`; relação opcional com `projeto`. | Alto |
| `fluxo-navegacao.png` | Navegação de telas | Presente e citado | Deve remover/ajustar "tela do assistente virtual" se estiver como página separada, e incluir projetos/editor/detalhes. | `LoginPage`, `CadastroPage`, `HomePage`, `MeusProjetosPage`, `ProjetoDetalhesPage`, `EditorPage`, `MinhasGravacoesPage`, `DetalhesGravacaoPage`, `HistoricoPage`, `DashboardPage`, `ConfiguracoesPage`. | Alto |

## 8. Banco de dados e DER

Banco real:

- Nome: `assistente_musical.db`.
- Versão real atual: `9`.
- Arquivo central: `lib/database/app_database.dart`.
- Tabelas reais:
  - `usuario`;
  - `projeto`;
  - `gravacao`;
  - `comando_voz`;
  - `comando_personalizado`;
  - `historico_acao`;
  - `configuracao_app`.

Campos importantes que precisam aparecer:

- `usuario`: `id`, `nome`, `email`, `senha_hash`, `senha_salt`, `senha_algoritmo`, `senha_iteracoes`, `senha_versao`, `auth_provider`, `google_id`, `foto_url`, `data_cadastro`.
- `projeto`: `id`, `usuario_id`, `nome`, `descricao`, `data_criacao`.
- `gravacao`: `id`, `usuario_id`, `projeto_id`, `nome`, `caminho_arquivo`, `data_criacao`, `duracao_segundos`, `status`, `tamanho_bytes`, `formato_audio`.
- `comando_voz`: `id`, `usuario_id`, `texto_reconhecido`, `tipo_comando`, `status_reconhecimento`, `acao_executada`, `data_hora`.
- `comando_personalizado`: `id`, `usuario_id`, `frase`, `tipo_comando`, `ativo`, `data_criacao`.
- `historico_acao`: `id`, `usuario_id`, `gravacao_id`, `projeto_id`, `tipo`, `descricao`, `data_hora`.
- `configuracao_app`: `id`, `comandos_voz_ativos`, `primeira_execucao_concluida`, `escuta_continua`, `feedback_sonoro`, `parada_silencio`, `tempo_silencio_segundos`, `tema_escuro`, `data_atualizacao`.

Divergências de nomes:

- `id_usuario` no TCC deve ser `id` na tabela real `usuario`.
- `senha` no TCC deve ser `senha_hash` mais campos de PBKDF2/salt.
- `historico_gravacao` no TCC deve ser `historico_acao`.
- `id_gravacao` no TCC deve ser `id` em `gravacao`.
- `duracao` no TCC deve ser `duracao_segundos`.
- `arquivo_audio`, `feedback` e `dashboard_indicador` não existem como tabelas reais.
- `projeto`, `comando_personalizado` e `configuracao_app` faltam no script do TCC.

Necessidade de atualizar script do banco: **crítica**. O script atual não representa o projeto físico, nem as migrations v2 a v9. Também faltam índices reais, chaves estrangeiras com `ON DELETE`, `CHECK` de status da gravação e campos de segurança/autenticação.

## 9. Testes e validação

Resultados reais informados para registrar na atualização posterior:

```powershell
dart analyze
No issues found!

flutter test --reporter compact
00:20 +396: All tests passed!

flutter build apk --debug
Built build\app\outputs\flutter-apk\app-debug.apk

flutter test --coverage
00:30 +396: All tests passed!
```

O TCC atual não registra esse conjunto completo de evidências. O README local também ainda cita número antigo de testes em um trecho, enquanto `docs/validacao_final_tcc.md` registra evidência conhecida de 396 testes.

O teste físico em aparelho Android está em andamento e ainda não deve ser declarado como concluído. A documentação deve dizer que a validação automatizada e o build debug passaram, mas a validação manual em aparelho real permanece pendente/em execução para gravação, navegação por voz, Google Login, Gemini, permissões e comportamento do microfone.

Riscos na seção atual:

- CT11 declara execução Android compatível como aprovada, o que precisa ser revisto.
- A tabela de testes não cobre explicitamente Google Login, PBKDF2/migração de senha, comandos personalizados, configurações, detalhes da gravação, permissões negadas, logout centralizado, realtime experimental e cobertura.
- A validação voice-first experimental deve ficar como controlada/automatizada quando não houver evidência física real.

## 10. Manual técnico

Cobertura atual:

- instalação em ambiente de desenvolvimento;
- Flutter SDK, Android SDK, VS Code;
- `flutter pub get`;
- `flutter run`;
- permissão de microfone;
- uso básico do sistema;
- flag `USE_STREAM_FIRST_AUDIO=true`.

Lacunas:

- instalação do APK debug gerado em `build\app\outputs\flutter-apk\app-debug.apk`;
- execução com `dart-define` para `GEMINI_API_KEY`, `GEMINI_MODEL`, `GOOGLE_SERVER_CLIENT_ID`, `USE_STREAM_FIRST_AUDIO`, `STREAMING_STT_WEBSOCKET_URL`, `PICOVOICE_*` quando aplicável;
- configuração de Google Login;
- SHA-1 debug e necessidade de SHA-1/SHA-256 release antes de APK release;
- explicação de que não há backend para validação server-side do `idToken` Google;
- funcionamento offline parcial: banco, parser local e controles manuais; dependências online para Gemini/Google/STT cloud;
- comandos principais de voz por categoria;
- permissões Android e fluxo de permissão negada/permanentemente negada;
- problemas conhecidos: disputa de microfone entre `speech_to_text` e `record`, modo híbrido do editor, teste físico ainda em andamento, limitações de ruído/reconhecimento.

## 11. Riscos residuais que devem aparecer no TCC

- SQLite local sem criptografia em repouso.
- Senhas locais protegidas por PBKDF2-HMAC-SHA256 com salt, mas banco local ainda não é criptografado.
- API key mitigada por restrições no Google Cloud; não expor chave em relatório, prints ou logs.
- Necessidade de cadastrar SHA-1/SHA-256 de release antes de APK release final.
- Ausência de backend para validação server-side do `idToken` Google.
- Teste físico Android ainda em execução; não declarar como concluído.
- Reconhecimento de voz sujeito a ruído, qualidade do microfone, permissões e comportamento do Android.
- Modo híbrido do Editor: STT pausado durante gravação para evitar disputa de microfone.
- Recursos realtime, wake-word, TTS, foreground service e streaming STT devem ser descritos como experimentais quando dependerem de flags/configuração ou ainda não tiverem validação física.
- Dependência de rede para Gemini, Google Login e STT cloud experimental.

## 12. Prioridade de correção

### Crítico

- Atualizar DER e script SQL para o banco real v9.
- Remover ou reescrever tabelas inexistentes no projeto físico: `arquivo_audio`, `feedback`, `dashboard_indicador`, `historico_gravacao`.
- Corrigir declarações de teste físico Android concluído/aprovado.

### Alto

- Atualizar RF/RNF para cobrir funcionalidades reais.
- Atualizar casos de uso para projetos, configurações, Google Login, comandos personalizados, detalhes de gravação, busca e logout.
- Atualizar diagramas de classe, sequência, caso de uso e navegação.
- Atualizar relatório de testes com os resultados reais informados e com a separação entre automatizado/build e físico.
- Atualizar manual técnico com APK, permissões, Google/SHA-1, offline parcial e problemas conhecidos.

### Médio

- Atualizar fundamentação para NLU/Gemini, segurança local e arquitetura experimental.
- Atualizar capturas/telas faltantes em protótipo.
- Ajustar conclusão e limitações.
- Documentar dashboard com insights locais.

### Baixo

- Revisar nomenclatura textual para evitar termos genéricos que não correspondem a classes/tabelas reais.
- Corrigir eventuais textos com mojibake em etapa própria, sem alterar formatação ABNT/UTP indevidamente.
- Verificar se imagens não referenciadas ainda devem permanecer no pacote Overleaf.

## 13. Plano de atualização sugerido

1. Congelar a estrutura ABNT/UTP do Overleaf e trabalhar somente em conteúdo textual/figuras quando a próxima etapa permitir.
2. Atualizar primeiro o banco: DER, modelagem de dados e script SQL a partir de `AppDatabase` v9 e `tables/*.dart`.
3. Atualizar requisitos RF/RNF e rastrear cada novo requisito para caso de uso e teste.
4. Revisar casos de uso existentes, removendo fluxos idealizados e adicionando fluxos reais de erro.
5. Atualizar diagramas UML a partir do código real. Priorizar caso de uso, sequência de autenticação, sequência de gravação/editor, classes principais, DER e navegação.
6. Atualizar relatório de testes com as evidências reais: `dart analyze`, 396 testes, build debug e coverage. Declarar teste físico Android como em andamento.
7. Atualizar manual técnico com instalação do APK, execução via Flutter, permissões, Google Login, SHA-1/SHA-256, flags, offline parcial, comandos e problemas conhecidos.
8. Atualizar demonstração de resultados, conclusão, limitações e riscos residuais.
9. Só depois revisar imagens/capturas se necessário, preservando layout e padrão ABNT/UTP.
10. Fazer uma auditoria final de aderência entre projeto lógico e projeto físico antes da entrega.

