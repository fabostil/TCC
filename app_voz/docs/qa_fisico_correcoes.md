# Correções do Teste Físico Android

## 1. Contexto

O teste físico em Android revelou problemas funcionais e de UX que serão corrigidos em etapas separadas, com foco em estabilidade para a apresentação do TCC. Esta etapa F.0 prepara a branch para esse ciclo, registra o baseline técnico e não implementa nenhuma correção no aplicativo.

## 2. Baseline técnico antes das correções

* Branch atual: `feature/true-voice-first`.
* Git status inicial:

```text
M  .gitignore
?? docs/auditoria_tcc_overleaf.md
?? documentacao/
```

* Commit atual: `6ca134d`.
* Arquivos gerados modificados: `android/build/reports/problems/problems-report.html` não aparecia como modificado no status inicial, portanto não foi restaurado.
* Arquivos relacionados ao Overleaf/auditoria observados e preservados: `.gitignore`, `docs/auditoria_tcc_overleaf.md` e `documentacao/`.
* Nenhuma correção de app foi feita nesta etapa.

## 3. Regras do ciclo de correção

Cada correção só será considerada concluída quando tiver:

* diagnóstico do problema;
* causa provável ou causa confirmada;
* correção implementada;
* teste automatizado criado ou ajustado quando aplicável;
* dart analyze sem erro;
* flutter test --reporter compact passando;
* teste manual no celular descrito;
* git status revisado;
* commit separado.

## 4. Lista priorizada de etapas

### F.1 — Google Login

Objetivo: diagnosticar e corrigir ou tratar corretamente falha de login Google após seleção da conta.

### F.2 — Player de gravação

Objetivo: corrigir reprodução que funciona uma vez e depois não toca novamente.

### F.3 — Navegação autenticada

Objetivo: impedir que voltar/seta retorne indevidamente para Login após autenticação.

### F.4 — Fallback local sem GEMINI_API_KEY

Objetivo: garantir comandos essenciais sem depender exclusivamente de NLU externo.

### F.5 — Comandos globais de navegação

Objetivo: permitir comandos como Dashboard, Histórico, Configurações, Projetos e Gravações em todas as telas principais.

### F.6 — Aliases de comandos por contexto

Objetivo: aceitar variações naturais como “gravar”, “iniciar gravação”, “histórico”, “abrir histórico”, “voltar”, “início”.

### F.7 — Ciclo de vida da escuta por voz

Objetivo: garantir que a escuta seja retomada ao voltar/navegar entre telas.

### F.8 — Modal de confirmação

Objetivo: permitir confirmação/cancelamento sem quebrar a escuta, ou ao menos retomar escuta após fechar modal.

### F.9 — Editor Musical e conflitos entre voz/gravação/player

Objetivo: revisar comandos de gravação no editor e estados durante gravação/reprodução.

### F.10 — Comando “voltar para tela inicial”

Objetivo: fazer o comando ir para a Home, não apenas executar um pop simples.

### F.11 — Scroll por voz

Objetivo: adicionar comandos mínimos para rolar listas principais, se for seguro.

### F.12 — Comandos personalizados

Objetivo: revisar funcionamento real dos comandos personalizados e documentar limitações.

### F.13 — Remover textos técnicos da UI

Objetivo: substituir estados como sleeping/listeningCommand/processingCommand e caminhos internos por textos amigáveis.

### F.14 — Ortografia e acentuação

Objetivo: corrigir textos visíveis ao usuário sem alterar nomes técnicos internos.

### F.15 — Esqueci minha senha

Objetivo: adicionar opção visual honesta para protótipo, sem prometer recuperação por e-mail se não há backend.

### F.16 — Microcopy e mensagens amigáveis

Objetivo: melhorar mensagens de erro/sucesso/comando não entendido.

### F.17 — Acessibilidade mínima

Objetivo: revisar semanticLabel, botões sem texto, tamanho de toque e feedback visual mínimo.

### F.18 — Regressão automatizada final

Objetivo: rodar analyze, testes completos e revisar cobertura básica.

### F.19 — Build APK debug final

Objetivo: gerar APK debug final para teste físico 2.

### F.20 — Atualização do relatório de testes do TCC

Objetivo: registrar bugs encontrados, correções realizadas e resultado da validação física final.

## 5. Critério de bloqueio

Não se deve avançar para a próxima etapa se:

* dart analyze falhar;
* flutter test falhar;
* houver arquivo estranho modificado sem explicação;
* a correção não tiver teste automatizado quando aplicável;
* o problema ainda puder ser reproduzido no teste manual.

## 6. Estado final da etapa F.0

* Arquivos criados/modificados nesta etapa: `docs/qa_fisico_correcoes.md`.
* O arquivo do Gradle `android/build/reports/problems/problems-report.html` não foi limpo porque não estava modificado.
* Git status final esperado após esta etapa:

```text
M  .gitignore
?? docs/auditoria_tcc_overleaf.md
?? docs/qa_fisico_correcoes.md
?? documentacao/
```

## F.1 — Google Login

### Problema observado

No teste físico em Android, o botão "Entrar com Google" nas telas de Login e Cadastro abria a seleção de contas Google, mas o app não concluía o login após a escolha da conta.

### Diagnóstico

O fluxo já separava `GoogleAuthService` para identidade externa e `AuthService` para resolver o usuário local, mas ainda havia pontos frágeis:

* erros técnicos do plugin ou de token podiam chegar à UI de forma pouco amigável;
* falhas ao preparar o usuário local podiam ser exibidas como exceção genérica;
* o botão Google era colocado em loading, mas a página ainda passava `onPressed` ativo durante `_carregandoGoogle`, deixando risco de tentativa duplicada;
* token nulo, token vazio e dados essenciais vazios não eram tratados com a mesma mensagem segura.

Não foi possível provar apenas pelo código que o bug físico era causado por SHA-1 ausente, mas essa continua sendo hipótese técnica relevante quando a seleção de conta abre e a falha ocorre logo após escolher a conta.

### Correção realizada

* `GoogleAuthService` passou a converter token/dados insuficientes em erro controlado com mensagem amigável.
* `GoogleAuthService` passou a converter `PlatformException` de configuração/sign-in em mensagem segura, sem expor detalhes técnicos ou credenciais.
* `AuthService` passou a converter erro ao criar/buscar usuário local em `AuthGoogleLoginException`.
* `LoginPage` e `CadastroPage` passaram a bloquear reentrada no fluxo Google enquanto a tentativa está em andamento.
* `LoginPage` e `CadastroPage` passaram a exibir mensagens amigáveis para falha Google e falha de preparação de conta.
* O cancelamento continua retornando ao estado normal, sem navegação e sem mensagem assustadora.

### Testes automatizados

Testes criados/alterados:

* `test/features/voices/services/google_auth_service_test.dart`
  * cancelamento retorna `null`;
  * identidade válida retorna `GoogleIdentity`;
  * token nulo, vazio ou em branco gera erro controlado;
  * e-mail vazio gera erro controlado;
  * `PlatformException` de configuração gera mensagem amigável;
  * erro ao obter autenticação/tokens vira erro controlado;
  * `signOut` continua funcionando.
* `test/features/voices/services/auth_service_test.dart`
  * identidade válida resolve usuário local;
  * cancelamento não cria usuário;
  * erro do provedor Google é propagado de forma controlada;
  * erro no resolvedor local vira falha amigável de preparação de conta.
* `test/features/voices/pages/login_page_test.dart`
  * sucesso com Google navega para Home;
  * erro de Google Login mostra mensagem amigável;
  * cancelamento não navega;
  * tentativa duplicada no botão Google é ignorada durante loading.
* `test/features/voices/pages/cadastro_page_test.dart`
  * sucesso com Google navega para Home;
  * erro de Google Login mostra mensagem amigável;
  * cancelamento não navega;
  * tentativa duplicada no botão Google é ignorada durante loading.

Validações executadas:

```text
dart analyze
No issues found!

flutter test --reporter compact
00:19 +404: All tests passed!
```

### Teste manual recomendado

1. Instalar/rodar app no Android.
2. Abrir tela de Login.
3. Tocar em "Entrar com Google".
4. Cancelar seleção de conta e verificar se app não trava.
5. Tocar novamente em "Entrar com Google".
6. Selecionar conta.
7. Verificar se entra na Home ou se mostra mensagem amigável.
8. Repetir na tela de Cadastro.

### Observação sobre SHA-1

Se o login com Google continuar abrindo a seleção de conta, mas falhar após escolher a conta em outro computador/dispositivo, é necessário conferir se o SHA-1 debug do ambiente de build do testador está cadastrado no Firebase/Google Cloud. O testador deve enviar apenas os valores SHA1 e SHA-256 gerados pelo comando signingReport. Nunca enviar keystore, senha, arquivo .jks, API key, google-services.json ou tokens.

Comando para o testador:

```powershell
cd android
.\gradlew signingReport
```

## F.2 — Player de gravação

### Problema observado

No teste físico em Android, uma gravação reproduzia corretamente na primeira tentativa, mas depois do término natural do áudio novas tentativas de play na mesma gravação não tocavam. Em alguns fluxos, a interface também podia permanecer indicando reprodução mesmo após o áudio já ter terminado.

### Diagnóstico

A causa confirmada no código estava em `AudioPlayerService`: o listener de `playerStateStream` tratava `ProcessingState.completed` apenas liberando a sessão de áudio no `VoiceSessionManager`. O serviço não reposicionava a fonte atual no início nem marcava que o mesmo caminho precisava reiniciar do começo. Assim, ao tocar o mesmo arquivo depois do fim natural, o player podia continuar no fim da mídia e a nova chamada de `play()` não reiniciava a reprodução.

Também foi confirmado que as telas e controllers já escutavam `state.playing == false` para limpar o estado visual de reprodução. Por isso a correção principal ficou no serviço de player, sem redesenhar telas.

### Correção realizada

* `AudioPlayerClient` recebeu suporte a `seek(Duration)`.
* `JustAudioPlayerClient` passou a delegar `seek` para o `just_audio`.
* `AudioPlayerService` passou a:
  * detectar `ProcessingState.completed`;
  * liberar a sessão de áudio com `playback_completed`;
  * reposicionar a mídia atual para `Duration.zero`;
  * marcar o caminho atual para reinício caso o reset assíncrono falhe;
  * permitir novo play da mesma gravação após término natural;
  * manter o comportamento de ignorar com segurança play duplicado enquanto a mesma gravação já está tocando;
  * marcar reprodução parada por `stop()` para reiniciar do começo no próximo play.

### Testes automatizados

Testes alterados em `test/features/editor/services/audio_player_service_test.dart`:

* play de arquivo válido inicia reprodução e atualiza `currentPath`;
* play da mesma gravação enquanto já está tocando não prepara player duplicado;
* conclusão natural reseta estado e chama `seek(Duration.zero)`;
* o mesmo arquivo pode tocar novamente depois da conclusão natural;
* `stop()` libera estado e permite tocar o mesmo arquivo novamente;
* erro em `setFilePath` libera sessão e não deixa player como playing;
* erro em `play` libera sessão e não deixa player como playing;
* `dispose` cancela assinatura e descarta recursos.

Validações executadas:

```text
dart analyze
No issues found!

flutter test --reporter compact
00:19 +407: All tests passed!

flutter build apk --debug
Built build\app\outputs\flutter-apk\app-debug.apk
```

### Teste manual recomendado

1. Rodar app no Android físico.
2. Fazer login.
3. Criar ou abrir um projeto.
4. Entrar no editor.
5. Gravar um áudio curto.
6. Salvar/encerrar gravação.
7. Abrir a gravação.
8. Tocar play uma vez.
9. Esperar o áudio terminar naturalmente.
10. Tocar play de novo na mesma gravação.
11. Confirmar que reproduz novamente.
12. Repetir pelo menos 3 vezes.
13. Testar stop/pause, se a tela oferecer.
14. Sair da tela, voltar e reproduzir novamente.

### Critério de aprovação manual

A etapa só passa manualmente se a mesma gravação puder ser reproduzida repetidas vezes sem reiniciar o app.

## F.3 — Navegação autenticada

### Problema observado

Durante o teste físico Android, voltar pela seta, pelo botão voltar do Android ou por ações de retorno podia levar o usuário de volta para Login/Cadastro mesmo após autenticação bem-sucedida.

### Diagnóstico

A causa confirmada estava na navegação de sucesso autenticado:

* `LoginPage` usava `Navigator.pushReplacement` após login local e Google Login.
* `CadastroPage` usava `Navigator.pushReplacement` após Google Login.
* Quando o Cadastro era aberto a partir do Login com `Navigator.push`, o Google Login do Cadastro substituía apenas a rota de Cadastro por Home, deixando a rota de Login atrás na pilha.
* O logout da `HomePage` já usava `Navigator.pushAndRemoveUntil` para limpar a área autenticada e voltar ao Login.

Não foram encontrados fluxos internos autenticados apontando diretamente para Login fora do logout explícito.

### Correção realizada

* `LoginPage` passou a usar navegação autenticada com `Navigator.of(context).pushAndRemoveUntil(..., (route) => false)` após sucesso no login local.
* `LoginPage` passou a usar o mesmo fluxo após sucesso no Google Login.
* `CadastroPage` passou a usar o mesmo fluxo após sucesso no Google Login.
* O cadastro local foi preservado: ele continua levando o usuário para Login, porque essa é a regra atual do protótipo para cadastro por e-mail.
* O logout foi preservado, mantendo limpeza de pilha e retorno ao Login.

### Testes automatizados

Testes criados/alterados:

* `test/features/voices/pages/login_page_test.dart`
  * login local com sucesso navega para Home;
  * login local com sucesso remove rotas anteriores da pilha;
  * Google Login com sucesso navega para Home;
  * Google Login com sucesso não revela Login ao simular voltar do Android;
  * fluxo Login → Cadastro → Google Login limpa Login e Cadastro da pilha;
  * cancelamento/erro de Google Login continuam sem navegar.
* `test/features/voices/pages/cadastro_page_test.dart`
  * Google Login com sucesso navega para Home;
  * Google Login com sucesso remove Cadastro e rotas anteriores da pilha;
  * cancelamento/erro continuam sem navegar;
  * cadastro local continua navegando para Login.
* `test/features/home/pages/home_page_test.dart`
  * logout confirmado leva para Login;
  * após logout, voltar não retorna para Home autenticada.

Validações executadas:

```text
dart analyze
No issues found!

flutter test --reporter compact
00:19 +412: All tests passed!

flutter build apk --debug
Built build\app\outputs\flutter-apk\app-debug.apk
```

### Teste manual recomendado

1. Rodar o app no Android físico.
2. Fazer login local.
3. Na Home, apertar o botão voltar do Android.
4. Confirmar que não volta para Login indevidamente.
5. Entrar novamente se necessário.
6. Abrir Meus Projetos.
7. Abrir um projeto.
8. Abrir Editor.
9. Usar seta de voltar/AppBar e botão voltar do Android.
10. Confirmar que retorna para telas internas esperadas, não para Login.
11. Repetir com Google Login, se configurado.
12. Fazer logout.
13. Confirmar que logout leva para Login.
14. Após logout, apertar voltar e confirmar que não retorna para Home autenticada.

### Critério de aprovação manual

A etapa só passa manualmente se Login/Cadastro não aparecerem ao usar voltar depois de autenticação, exceto após logout explícito.

## F.4 — Fallback local sem GEMINI_API_KEY

### Problema observado

Durante o teste físico Android, comandos básicos como Dashboard, Histórico e Configurações podiam cair em uma mensagem técnica pedindo configuração de `GEMINI_API_KEY`.

Esse comportamento expunha uma dependência interna ao usuário final e fazia comandos essenciais dependerem de NLU externo, mesmo quando a intenção poderia ser resolvida localmente.

### Diagnóstico

A ordem de interpretação já estava correta em `VoiceCommandController`: primeiro `CommandService`, depois comandos personalizados e só então `AiCommandService` quando a IA estivesse configurada.

A causa confirmada estava em dois pontos:

* o parser local não reconhecia algumas formas essenciais isoladas, como `dashboard`, `historico`, `configuracoes`, `projetos`, `gravacoes`, `inicio` e `tela inicial`;
* a `HomePage` mostrava a mensagem técnica `Comando nao reconhecido. Configure GEMINI_API_KEY para NLU.` quando um comando chegava como desconhecido.

### Correção realizada

* `CommandService` passou a expor uma mensagem amigável única para comando desconhecido sem citar `GEMINI_API_KEY`.
* A normalização local passou a remover pontuação simples, além de minúsculas, acentos, cedilha, trim e espaços duplicados.
* O fallback local passou a reconhecer comandos essenciais de navegação:
  * `dashboard` e `abrir dashboard`;
  * `historico` e `abrir historico`;
  * `configuracoes` e `abrir configuracoes`;
  * `projetos`, `meus projetos` e `abrir projetos`;
  * `gravacoes`, `minhas gravacoes` e `abrir gravacoes`;
  * `novo projeto` e `criar projeto`.
* O fallback local passou a reconhecer retorno básico:
  * `voltar`;
  * `tela inicial`;
  * `inicio`;
  * `voltar para tela inicial`;
  * `ir para tela inicial`.
* Os comandos de gravação essenciais já existentes foram preservados e cobertos por testes adicionais:
  * `gravar`;
  * `iniciar gravacao`;
  * `comecar gravacao`;
  * `pausar gravacao`;
  * `retomar gravacao`;
  * `parar gravacao`;
  * `encerrar gravacao`.
* `HomePage` deixou de mostrar a mensagem técnica e passou a exibir:

```text
Não entendi o comando. Tente dizer: novo projeto, minhas gravações, dashboard ou configurações.
```

### Testes automatizados

Testes criados/alterados:

* `test/features/voices/services/command_service_test.dart`
  * normalização remove acentos, pontuação simples e espaços duplicados;
  * comandos essenciais de navegação são reconhecidos localmente;
  * comandos de retorno como `voltar para tela inicial` e `inicio` são reconhecidos;
  * comandos essenciais de gravação são reconhecidos localmente.
* `test/features/voices/controllers/voice_command_controller_test.dart`
  * comandos essenciais são resolvidos localmente sem chave da IA;
  * comando desconhecido sem IA permanece desconhecido sem acionar Gemini;
  * mensagem amigável não cita `GEMINI_API_KEY`.

Validações executadas:

```text
dart analyze
No issues found!

flutter test --reporter compact
00:27 +414: All tests passed!

flutter build apk --debug
Built build\app\outputs\flutter-apk\app-debug.apk
```

### Teste manual recomendado

1. Rodar o app no Android físico sem configurar `GEMINI_API_KEY`.
2. Fazer login.
3. Na Home, dizer:
   * "Dashboard"
   * "Histórico"
   * "Configurações"
   * "Meus projetos"
   * "Minhas gravações"
   * "Novo projeto"
4. Confirmar que nenhum desses comandos mostra mensagem "Configure GEMINI_API_KEY".
5. Dizer um comando desconhecido.
6. Confirmar que aparece mensagem amigável:

```text
Não entendi o comando. Tente dizer: novo projeto, minhas gravações, dashboard ou configurações.
```

### Critério de aprovação manual

A etapa só passa manualmente se comandos essenciais não dependerem da `GEMINI_API_KEY` e se o usuário não vir mensagem técnica.

## F.5 — Comandos globais de navegação

### Problema observado

Durante o teste físico Android, comandos de navegação funcionavam principalmente na Home, mas não eram executados de forma consistente em todas as telas principais autenticadas.

Exemplos práticos: a intenção `meus projetos` podia ser reconhecida fora da Home, mas a tela atual marcava o comando como indisponível; o mesmo podia acontecer com Dashboard, Histórico, Configurações e Gravações.

### Diagnóstico

A causa confirmada estava na execução dos comandos, não no parser:

* a F.4 já fazia `CommandService` reconhecer os comandos globais essenciais;
* `ContextualVoiceListeningMixin` centralizava a escuta/interpretação, mas delegava a execução para o `VoiceCommandDispatcher` de cada página;
* Home tratava navegação para as telas principais;
* várias telas autenticadas tinham dispatchers contextuais que retornavam `VoiceCommandPageResult.unavailable` para comandos como `abrirDashboard`, `abrirProjetos`, `abrirGravacoes`, `abrirHistorico` e `abrirConfiguracoes`;
* `ConfiguracoesPage` desativava o serviço global de configurações por voz para evitar duplicidade, então precisava de navegação global separada desse serviço;
* `EditorPage` não usa `ContextualVoiceListeningMixin` e mantém um fluxo próprio de comandos, por isso também precisava de integração própria.

### Correção realizada

* Criado `VoiceNavigationCommandHandler`, um handler central para classificar e executar comandos globais de navegação já interpretados pelo `CommandService`.
* `ContextualVoiceListeningMixin` passou a tentar navegação global antes do dispatcher contextual da página.
* `ConfiguracoesPage` passou a manter navegação global mesmo com `voiceHandlesGlobalCommands == false`.
* `EditorPage` recebeu integração direta com o mesmo handler, respeitando seu fluxo próprio.
* `criar projeto` foi tratado como navegação global fora de Meus Projetos, mas foi preservado como comando contextual de salvar/criar dentro de `MeusProjetosPage`.
* Para `tela inicial`/`inicio`, as páginas autenticadas usam `Navigator.popUntil(... route.isFirst)` para voltar à raiz autenticada sem empilhar Home repetida.
* Para `voltar`, as páginas usam `Navigator.maybePop`, preservando a pilha autenticada e sem navegar para Login.
* No Editor, a navegação global é bloqueada durante gravação ativa com mensagem segura, deixando os conflitos finos entre voz/gravação/player para F.9.

Telas integradas:

* `HomePage`
* `MeusProjetosPage`
* `ProjetoDetalhesPage`
* `MinhasGravacoesPage`
* `DetalhesGravacaoPage`
* `DashboardPage`
* `HistoricoPage`
* `ConfiguracoesPage`
* `EditorPage`

Comandos cobertos:

* `tela inicial`, `inicio`, `voltar para tela inicial`, `ir para tela inicial`
* `meus projetos`, `projetos`, `abrir projetos`
* `minhas gravacoes`, `gravacoes`, `abrir gravacoes`
* `dashboard`, `abrir dashboard`
* `historico`, `abrir historico`
* `configuracoes`, `abrir configuracoes`
* `novo projeto`, `criar projeto`
* `voltar`

### Testes automatizados

Testes criados:

* `test/features/voices/coordination/voice_navigation_command_handler_test.dart`
  * comandos globais chamam o callback correto;
  * destino atual não empilha a mesma rota;
  * `criar projeto` pode ser preservado como comando contextual em Meus Projetos;
  * comando desconhecido não é tratado pelo handler global.

Validações executadas:

```text
dart analyze
No issues found!

flutter test --reporter compact
00:29 +418: All tests passed!

flutter build apk --debug
Built build\app\outputs\flutter-apk\app-debug.apk
```

### Teste manual recomendado

1. Rodar app no Android físico.
2. Fazer login.
3. Na Home, dizer:
   * "Meus projetos"
   * "Minhas gravações"
   * "Dashboard"
   * "Histórico"
   * "Configurações"
4. Entrar em Meus Projetos e dizer:
   * "Minhas gravações"
   * "Configurações"
   * "Tela inicial"
5. Entrar em Minhas Gravações e dizer:
   * "Meus projetos"
   * "Dashboard"
   * "Tela inicial"
6. Entrar no Editor ou Detalhes de Gravação e dizer:
   * "Tela inicial"
   * "Configurações"
   * "Voltar"
7. Confirmar que nenhuma ação leva indevidamente para Login.
8. Confirmar que não aparece mensagem "Configure GEMINI_API_KEY".

### Critério de aprovação manual

A etapa só passa manualmente se comandos globais principais funcionarem fora da Home e não levarem o usuário para Login.

## F.6 - Aliases de comandos por contexto

### Problema observado

No teste fisico Android, varios comandos ainda dependiam de formulacoes muito exatas. Isso prejudicava a experiencia voice-first porque comandos naturais como "gravar", "vai para projetos", "meu painel", "dar play" ou "tema claro" podiam nao ser reconhecidos localmente e ficavam dependentes de NLU externo.

### Diagnostico

O `CommandService` ja normalizava minusculas, acentos, cedilha, pontuacao simples e espacos duplicados, e o `VoiceCommandController` ja preservava a ordem segura: parser local, comandos personalizados e Gemini apenas quando configurado. A limitacao estava na cobertura de aliases locais: navegacao, gravacao, reproducao, projetos e configuracoes tinham algumas frases principais, mas ainda faltavam variacoes naturais usadas no teste fisico.

Os handlers das telas ja tinham execucao real para as intencoes existentes:

* navegacao global via `VoiceNavigationCommandHandler`;
* gravacao no `EditorPage`;
* reproducao, detalhes e exclusao protegida nas telas de gravacoes;
* criacao, abertura, renomeacao e exclusao protegida em projetos;
* toggles existentes em configuracoes.

Por isso a correcao ficou concentrada em aliases locais e testes, sem alterar ciclo de vida da escuta, banco, auth, player, modais ou arquitetura das paginas.

### Correcao realizada

* Ampliados aliases globais de navegacao para Home/inicio, projetos, gravacoes, dashboard/painel/indicadores, historico, configuracoes/ajustes/preferencias, novo projeto e voltar.
* Ampliados aliases de gravacao para iniciar, pausar, retomar e encerrar usando variacoes como "gravar", "comecar a gravar", "dar pausa", "voltar a gravar" e "salvar gravacao".
* Ampliados aliases de reproducao e gravacoes para "tocar", "dar play", "ouvir gravacao", "ver detalhes" e verbos seguros de exclusao com alvo ou confirmacao posterior.
* Ampliados aliases de projetos para abrir, criar, excluir e renomear/editar quando a tela ja possui suporte.
* Ampliados aliases de configuracoes para tema escuro/claro, controle por voz, escuta continua e feedback sonoro.
* `home` isolado passou a ser tratado como retorno para a tela inicial no handler global.
* Mantida a protecao contra falsos positivos destrutivos: "apagar" sozinho continua desconhecido, e exclusao de projeto/gravacao continua exigindo alvo ou confirmacao existente na tela.
* Mantida a mensagem amigavel para comando desconhecido sem expor `GEMINI_API_KEY`.

### Testes automatizados

Testes criados/alterados:

* `test/features/voices/services/command_service_test.dart`
  * normalizacao com caixa alta, acentos, pontuacao e espacos;
  * aliases de navegacao, gravacao, reproducao, projetos e configuracoes;
  * aliases sem parametro que apenas disparam a intencao segura e deixam a tela pedir complemento;
  * comando destrutivo ambiguo "apagar" permanece desconhecido.
* `test/features/voices/coordination/voice_navigation_command_handler_test.dart`
  * aliases naturais de navegacao global chamam os callbacks corretos;
  * `home` isolado navega para a tela inicial;
  * `volta` executa retorno simples.

### Teste manual recomendado

1. Rodar app no Android fisico.
2. Fazer login.
3. Testar na Home:
   * "abre configuracoes"
   * "vai para projetos"
   * "ver indicadores"
   * "mostrar gravacoes"
4. Testar no Editor:
   * "gravar"
   * "comecar a gravar"
   * "pausa"
   * "continuar gravacao"
   * "finalizar gravacao"
5. Testar em Detalhes da Gravacao:
   * "tocar"
   * "dar play"
   * "ouvir gravacao"
6. Testar em Configuracoes:
   * "modo escuro"
   * "tema claro"
   * "ligar controle por voz"
   * "desligar feedback sonoro"
7. Confirmar que comandos desconhecidos continuam com mensagem amigavel.
8. Confirmar que acoes destrutivas ainda pedem confirmacao.

### Criterio de aprovacao manual

A etapa so passa se o app aceitar variacoes naturais dos comandos principais sem exigir frase exata e sem executar acoes destrutivas sem confirmacao.

## F.7 - Ciclo de vida da escuta por voz

### Problema observado

No teste fisico Android, a escuta por voz podia nao retomar depois de navegar e voltar entre telas autenticadas. O problema era mais perceptivel ao usar a seta da AppBar, o botao voltar do Android ou ao abrir uma tela por toque e retornar para a tela anterior.

### Diagnostico

A causa confirmada no codigo estava no ciclo de vida das rotas. O app ja possuia `VoiceRouteObserver` registrado no `MaterialApp`, e esse observer cancelava a escuta ao empilhar uma nova rota. Porem, o `ContextualVoiceListeningMixin` nao assinava o observer como `RouteAware` e nao recebia `didPopNext` quando a tela anterior voltava ao topo.

Tambem havia risco de uma tela coberta continuar aceitando transcricoes atrasadas, porque o mixin nao tinha um estado interno de rota ativa para bloquear processamento contextual enquanto outra tela estava no topo. Algumas paginas retomavam manualmente apos `Navigator.push`, mas esse comportamento nao era centralizado e nao cobria todos os caminhos de navegacao global.

### Correcao realizada

* A instancia global de `VoiceRouteObserver` foi centralizada em `lib/features/voices/coordination/voice_route_observer.dart`, permitindo que o `main.dart` e o mixin usem o mesmo observer.
* `ContextualVoiceListeningMixin` passou a implementar `RouteAware`.
* O mixin agora assina a rota atual em `didChangeDependencies` e cancela a assinatura em `disposeContextualVoiceListening`.
* `didPushNext` marca a pagina como inativa e pausa a escuta contextual da tela coberta.
* `didPopNext` marca a pagina como ativa novamente e chama `startContinuousVoiceListeningIfActive`.
* O processamento de comandos, callbacks de STT e reinicios continuos agora checam se a rota ainda esta ativa.
* A assinatura do observer e idempotente, evitando duplicidade quando `didChangeDependencies` roda mais de uma vez.

### Testes automatizados

Teste criado:

* `test/features/voices/coordination/contextual_voice_listening_mixin_test.dart`
  * tela ativa aceita processamento contextual;
  * tela coberta por outra rota nao processa comando contextual;
  * retorno por `didPopNext` solicita retomada uma unica vez;
  * dispose remove registro de rota e libera o owner de voz.

### Teste manual recomendado

1. Rodar app no Android fisico.
2. Fazer login.
3. Na Home, dizer "Meus projetos".
4. Em Meus Projetos, usar a seta de voltar/AppBar.
5. De volta a Home, dizer "Configuracoes".
6. Confirmar que o comando funciona.
7. Em Configuracoes, apertar voltar do Android.
8. De volta a Home ou tela anterior, dizer "Dashboard".
9. Confirmar que o comando funciona.
10. Abrir Minhas Gravacoes por voz.
11. Voltar por botao Android.
12. Dizer "Meus projetos".
13. Confirmar que funciona.
14. Abrir Editor sem gravacao ativa.
15. Voltar.
16. Dizer "Configuracoes".
17. Confirmar que funciona.
18. Confirmar que nenhum comando e executado duplicado.

### Criterio de aprovacao manual

A etapa so passa se a escuta por voz continuar funcionando depois de navegar e voltar entre telas principais, sem precisar reiniciar o app e sem executar comandos duplicados.

## F.8 - Confirmacao por voz em modais

### Problema observado

Durante o QA fisico, modais de confirmacao podiam impedir que o usuario respondesse por voz com "confirmar", "sim", "cancelar" ou "nao". Isso quebrava o fluxo voice-first em acoes destrutivas, porque o app mostrava a confirmacao visual, mas nao havia um estado central de confirmacao pendente ligado ao dialogo.

### Diagnostico

Os dialogos visuais de exclusao e saida eram abertos por `showDialog` ou `AppFeedback.confirm`, mas nao registravam uma confirmacao pendente para comandos de voz. A F.7 corrigiu o ciclo de vida de paginas com `RouteAware`, mas `DialogRoute` nao ativava um listener contextual proprio para o modal.

Tambem foi confirmado um risco em `DetalhesGravacaoPage`: o comando contextual `confirmarAcao` chamava a exclusao confirmada diretamente, mesmo sem uma confirmacao pendente. Esse comportamento foi removido para impedir acao destrutiva sem contexto.

### Correcao realizada

* Criado `VoiceConfirmationController` para registrar uma confirmacao pendente, aceitar apenas confirmacao/cancelamento enquanto ela existir e bloquear comandos desconhecidos ou globais durante o modal.
* `ContextualVoiceListeningMixin` passou a expor `showVoiceConfirmationDialog`, que registra a confirmacao do dialogo, permite fechar por voz e retoma a escuta contextual ao fechar quando as flags de voz da pagina continuam ativas.
* A confirmacao pendente e limpa ao confirmar, cancelar, fechar pelo botao voltar ou destruir a tela.
* O mixin passou a aceitar comandos de confirmacao mesmo quando o comando anterior abriu o modal e ainda esta aguardando o resultado.
* Foram integrados os modais principais de exclusao de projeto, exclusao de gravacao, exclusao de gravacao em detalhes de projeto, exclusao em detalhes da gravacao e saida da sessao.
* `confirmar` ou `sim` fora de confirmacao pendente nao executam exclusao.
* Comandos globais, como "configuracoes", ficam bloqueados enquanto uma confirmacao destrutiva esta pendente.

Comandos aceitos para confirmar:

* "confirmar"
* "confirmo"
* "sim"
* "pode confirmar"
* "confirmar exclusao"

Comandos aceitos para cancelar:

* "cancelar"
* "cancela"
* "nao"
* "desistir"
* "voltar"

### Testes automatizados

Testes criados/alterados:

* `test/features/voices/coordination/voice_confirmation_controller_test.dart`
  * "sim" sem pendencia nao executa nada;
  * "sim" e "confirmar exclusao" confirmam quando ha pendencia;
  * "cancelar" e "nao" cancelam e limpam estado;
  * comando desconhecido nao confirma;
  * comando global fica bloqueado durante confirmacao.
* `test/features/voices/coordination/contextual_voice_listening_mixin_test.dart`
  * modal confirma por voz e fecha;
  * modal cancela por voz e limpa pendencia;
  * escuta e retomada apos o modal.

### Teste manual recomendado

1. Rodar app no Android fisico.
2. Fazer login.
3. Criar ou abrir projeto.
4. Criar/gravar uma gravacao de teste.
5. Pedir/tocar para excluir gravacao.
6. Quando o modal aparecer, dizer "cancelar".
7. Confirmar que a gravacao nao foi excluida.
8. Repetir e dizer "confirmar".
9. Confirmar que a gravacao foi excluida.
10. Criar ou abrir um projeto.
11. Pedir/tocar para excluir projeto.
12. No modal, dizer "nao".
13. Confirmar que projeto nao foi excluido.
14. Repetir e dizer "confirmar exclusao".
15. Confirmar que o projeto foi excluido.
16. Apos cada modal fechado, dizer "Configuracoes" ou "Meus projetos".
17. Confirmar que a escuta continua funcionando.
18. Dizer "sim" fora de qualquer modal.
19. Confirmar que nada destrutivo acontece.

### Criterio de aprovacao manual

A etapa so passa se modais principais aceitarem confirmacao/cancelamento por voz com seguranca e a escuta continuar funcionando apos o modal fechar.

## F.9 - Editor Musical: voz, gravacao, reproducao e saida segura

### Problema observado

No QA fisico, o Editor Musical apresentou inconsistencias entre comandos de voz, gravacao, reproducao e retorno. O risco principal era sair ou navegar durante uma gravacao ativa sem uma regra clara de preservacao do audio, alem de deixar a escuta de voz incoerente apos gravar ou reproduzir.

### Diagnostico

O `EditorPage` nao usa `ContextualVoiceListeningMixin`; ele possui fluxo proprio porque coordena `speech_to_text`, `record` e player no mesmo ponto. O codigo ja pausava a escuta antes de iniciar a gravacao para evitar disputa real de microfone no Android, e o `RecordingRealtimeCoordinator` mantinha a gravacao como dono do audio ate o stop.

Tambem foi confirmado que a navegacao global do Editor passava por `VoiceNavigationCommandHandler`, mas durante gravacao ativa apenas bloqueava navegacao com mensagem generica. O AppBar/back ja usava `PopScope`, mas o modal tinha texto antigo e nao deixava tao explicito que a acao segura era encerrar/salvar antes de sair. Na reproducao, o player ja preservava a correcao da F.2, mas o Editor nao marcava uma retomada explicita da escuta ao final do playback.

### Correcao realizada

* Criada `EditorVoiceFlowPolicy` para centralizar a regra testavel do Editor:
  * comandos globais sao permitidos sem gravacao ativa;
  * navegacao global e bloqueada durante gravacao ativa;
  * `voltar` e `sair` durante gravacao exigem confirmacao de encerramento.
* O comando `voltar` durante gravacao agora abre a confirmacao segura em vez de apenas devolver uma mensagem.
* O comando `sair` durante gravacao usa a mesma regra de confirmacao.
* O modal do Editor foi ajustado para:
  * titulo `Gravacao em andamento`;
  * mensagem explicita sobre encerrar a gravacao e sair;
  * botoes `Continuar gravando` e `Encerrar e sair`.
* A acao confirmada encerra/salva a gravacao antes de sair do Editor.
* Cancelar a confirmacao mantem o usuario no Editor e tenta retomar a escuta continua quando aplicavel.
* A reproducao dentro do Editor cancela a escuta antes do playback e marca retomada unica ao terminar ou parar.
* O `RecordingRealtimeCoordinator` continua impedindo reproducao enquanto ha gravacao ativa.

Limitacao mantida: no modo legado Android, `speech_to_text` e `record` disputam o microfone. Por isso, durante gravacao ativa, a escuta por voz fica pausada e o usuario deve usar os controles da tela para pausar/encerrar. O app nao promete comando por voz durante gravacao nesse modo.

### Testes automatizados

Testes criados/alterados:

* `test/features/editor/pages/editor_voice_flow_policy_test.dart`
  * comandos globais sao permitidos quando nao ha gravacao ativa;
  * navegacao global e bloqueada durante gravacao ativa;
  * `voltar` e `sair` durante gravacao exigem confirmacao;
  * mensagem de indisponibilidade de voz durante gravacao fica documentada.
* `test/features/editor/controllers/recording_realtime_coordinator_test.dart`
  * playback concluido reseta estado de reproducao;
  * playback nao inicia durante gravacao ativa.

### Teste manual recomendado

1. Rodar app no Android fisico.
2. Fazer login.
3. Criar ou abrir projeto.
4. Abrir Editor.
5. Sem gravar, dizer "Configuracoes" e confirmar que navega.
6. Voltar ao Editor.
7. Dizer "gravar" ou "comecar a gravar".
8. Confirmar que gravacao inicia.
9. Durante gravacao, tentar "tela inicial" ou "configuracoes".
10. Confirmar que o app nao sai de forma insegura.
11. Tentar voltar pela AppBar ou botao Android.
12. Confirmar que aparece confirmacao segura.
13. Cancelar e confirmar que continua no Editor.
14. Encerrar/salvar gravacao.
15. Confirmar que escuta volta.
16. Reproduzir gravacao.
17. Esperar terminar.
18. Confirmar que pode usar voz novamente.
19. Reproduzir novamente e confirmar que F.2 continua funcionando.

### Criterio de aprovacao manual

A etapa so passa se o Editor nao perder audio ao sair, nao permitir navegacao insegura durante gravacao e continuar com escuta funcional apos parar gravacao/reproducao.

## F.10 - Comando "voltar para tela inicial"

### Problema observado

No QA fisico, comandos como "voltar para tela inicial" e "voltar para o inicio" podiam se comportar como um simples voltar, fazendo apenas um `pop` da rota atual. Em pilhas profundas, isso nao leva diretamente para a Home autenticada.

### Diagnostico

O `CommandService` mapeava tanto "voltar" simples quanto comandos de Home para `VoiceCommandType.voltar`. A separacao real ficava em `VoiceNavigationCommandHandler`, que olhava o texto normalizado para decidir entre `goBack` e `goHome`.

Foi confirmado que o handler ja tratava `inicio`, `home`, `tela inicial`, textos com `tela inicial`, `para home` e `ir para home` como Home. A lacuna estava em frases como `voltar para o inicio`, `voltar para inicio` e `ir para o inicio`, que eram reconhecidas como `voltar`, mas nao eram classificadas como destino Home. Tambem faltava o alias local `abre tela inicial` no parser.

### Correcao realizada

* `CommandService` passou a reconhecer `abre tela inicial`.
* `VoiceNavigationCommandHandler` passou a centralizar a classificacao em `isHomeNavigationCommand`.
* `voltar` e `voltar uma tela` continuam usando `goBack`.
* `tela inicial`, `inicio`, `home`, `voltar para tela inicial`, `voltar para o inicio`, `ir para o inicio`, `abre tela inicial` e `abrir tela inicial` usam `goHome`.
* Quando a tela atual ja e Home, o handler retorna `Tela inicial ja esta aberta.` sem chamar `goHome`, evitando duplicar Home.
* Nas telas autenticadas existentes, `goHome` continua usando o fluxo ja estabelecido de `Navigator.popUntil(... route.isFirst)`, preservando a protecao da F.3 contra retorno ao Login depois da autenticacao.
* No Editor com gravacao ativa, a regra da F.9 permanece: comandos do tipo `voltar`, incluindo comandos de Home, passam pela confirmacao segura em vez de sair silenciosamente.

### Testes automatizados

Testes criados/alterados:

* `test/features/voices/services/command_service_test.dart`
  * cobre `tela inicial`, `home`, `inicio`, `voltar para tela inicial`, `voltar para o inicio`, `ir para o inicio`, `abre tela inicial` e `abrir tela inicial`.
* `test/features/voices/coordination/voice_navigation_command_handler_test.dart`
  * diferencia `voltar`/`voltar uma tela` de comandos diretos para Home;
  * valida que pilha profunda chama `goHome`, nao `goBack`;
  * valida que Home atual nao duplica rota.

### Teste manual recomendado

1. Rodar app no Android fisico.
2. Fazer login.
3. Na Home, dizer "tela inicial" e confirmar que nao duplica tela.
4. Ir para Meus Projetos e dizer "tela inicial".
5. Confirmar retorno direto para Home.
6. Ir para Projeto -> Detalhes -> Editor sem gravar.
7. Dizer "voltar para tela inicial".
8. Confirmar retorno direto para Home.
9. Ir para Configuracoes e dizer "home".
10. Confirmar retorno para Home.
11. Ir para Editor, iniciar gravacao.
12. Dizer "tela inicial".
13. Confirmar que nao sai de forma insegura nem perde audio.
14. Dizer "voltar" em uma tela comum e confirmar que volta uma tela, nao necessariamente Home.
15. Confirmar que em nenhum caso retorna para Login sem logout.

### Criterio de aprovacao manual

A etapa so passa se "tela inicial"/"home"/"voltar para tela inicial" levarem a Home autenticada diretamente, enquanto "voltar" simples continua como retorno comum e nenhum fluxo cai no Login.

## F.11 - Scroll por voz

### Problema observado

Listas longas ainda dependiam de toque para rolar. Isso prejudicava o uso hands-free em telas como projetos, gravacoes, historico, dashboard e configuracoes.

### Diagnostico

O `CommandService` nao possuia intencoes de scroll. As telas principais ja recebiam comandos contextuais pelo `ContextualVoiceListeningMixin`, mas seus `ListView` nao tinham `ScrollController` compartilhado com um handler de voz. Tambem foi confirmado que comandos globais continuam passando antes do dispatcher contextual, preservando navegacao como "voltar" e "tela inicial".

### Correcao realizada

* Adicionados comandos locais de scroll:
  * baixo: "rolar para baixo", "descer", "desce", "mais para baixo", "baixo", "proximos", "ver mais";
  * cima: "rolar para cima", "subir", "sobe", "mais para cima", "cima", "anteriores";
  * topo: "ir para o topo", "voltar para o topo", "topo", "comeco da lista";
  * fim: "ir para o fim", "fim da lista", "final da lista", "ultimos".
* Criado `VoiceScrollHandler` para centralizar a rolagem por voz com `ScrollController`.
* O handler verifica `hasClients`, limita o destino entre topo e fim e usa animacao curta.
* Telas integradas:
  * Meus Projetos;
  * Detalhes do Projeto;
  * Minhas Gravacoes;
  * Detalhes da Gravacao;
  * Historico;
  * Dashboard;
  * Configuracoes.
* Quando nao ha lista rolavel, o app responde com mensagem amigavel.
* "voltar" continua sendo navegacao comum e "tela inicial" continua indo para Home autenticada, sem virar topo da lista.
* O Editor nao recebeu scroll interno nesta etapa; quando recebe comando de scroll, informa que nao ha lista para rolar, preservando o fluxo especial de gravacao/reproducao da F.9.

### Testes automatizados

Testes criados/alterados:

* `test/features/voices/services/command_service_test.dart`
  * reconhece comandos de scroll para baixo, cima, topo e fim;
  * valida que "voltar" continua sendo voltar;
  * valida que "tela inicial" continua sendo Home/navegacao, nao topo.
* `test/features/voices/coordination/voice_scroll_handler_test.dart`
  * sem `ScrollController` anexado nao quebra;
  * scroll para baixo aumenta o offset;
  * scroll para cima reduz o offset;
  * topo vai para `0`;
  * fim vai para `maxScrollExtent`;
  * destinos ficam dentro dos limites.

### Teste manual recomendado

1. Rodar app no Android fisico.
2. Fazer login.
3. Criar varios projetos ou usar lista existente.
4. Em Meus Projetos, dizer "descer".
5. Confirmar que a lista rola para baixo.
6. Dizer "subir".
7. Confirmar que rola para cima.
8. Dizer "ir para o fim".
9. Confirmar que vai ao final.
10. Dizer "ir para o topo".
11. Confirmar que volta ao comeco.
12. Repetir em Minhas Gravacoes.
13. Repetir em Historico, se houver lista.
14. Confirmar que "voltar" continua voltando tela, nao rolando.
15. Confirmar que "tela inicial" continua indo para Home, nao para topo da lista.

### Criterio de aprovacao manual

A etapa so passa se listas principais puderem ser roladas por voz sem quebrar comandos globais de navegacao.

## F.12 - Comandos personalizados

### Problema observado

A funcionalidade de comandos personalizados ja existia no app, mas precisava ser validada de ponta a ponta para confirmar se salvar, listar, reconhecer por voz e proteger comandos reservados funcionavam sem depender do Gemini.

### Diagnostico

Foi confirmado no codigo que a tabela `comando_personalizado` ja existe no SQLite com `id`, `usuario_id`, `frase`, `tipo_comando`, `ativo` e `data_criacao`, alem de `UNIQUE(usuario_id, frase)`.

O repository ja salvava, listava por usuario, listava ativos, alternava ativo/inativo e excluia comandos. A tela de Configuracoes ja tinha formulario, lista, switch de ativo e botao de exclusao.

O `VoiceCommandController` ja usava a ordem correta: `CommandService` local, depois `CustomCommandService`, e somente depois `AiCommandService` quando configurado. Assim, comandos personalizados funcionavam sem `GEMINI_API_KEY` e comandos globais continuavam com prioridade.

As lacunas confirmadas estavam nas validacoes antes do salvamento:

* frase reservada como `voltar` ou `tela inicial` podia ser cadastrada, embora nao sobrescrevesse a execucao global por causa da prioridade do controller;
* frase duplicada era protegida apenas por igualdade literal no banco, sem considerar normalizacao como acentos, pontuacao e espacos duplicados;
* frase composta apenas por pontuacao podia passar pela validacao inicial de tamanho;
* faltavam testes diretos do `CustomCommandService` e da integracao com `VoiceCommandController`.

Nao foi identificada necessidade de alterar schema ou migration.

### Correcao realizada

* Criado `CustomCommandRules` em `custom_command_service.dart` para centralizar normalizacao e deteccao de frase reservada usando a mesma regra do `CommandService`.
* `SettingsController.saveCustomCommand` passou a validar:
  * usuario autenticado;
  * frase normalizada nao vazia;
  * minimo de 3 caracteres normalizados;
  * tipo de acao valido no catalogo;
  * frase reservada do app;
  * duplicata normalizada para o mesmo usuario.
* A validacao do formulario em `ConfiguracoesPage` passou a rejeitar frase que vira vazia apos normalizacao.
* O schema do banco foi preservado.
* A exclusao continua direta pelo botao existente; nao foi adicionada confirmacao nova nesta etapa para manter o escopo restrito.
* A execucao real continua limitada as acoes ja existentes no `CustomCommandCatalog`, mapeadas para frases canonicas do `CommandService`.

### Regra de prioridade

Ordem confirmada e testada:

1. `CommandService` local.
2. `CustomCommandService`, apenas se houver `usuarioId`.
3. `AiCommandService`, apenas se configurado.
4. Comando desconhecido com mensagem amigavel.

Comando personalizado nao sobrescreve comandos criticos como voltar, sair, confirmar, cancelar, tela inicial, exclusao ou gravacao, porque frases reconhecidas pelo `CommandService` sao bloqueadas no cadastro e tambem continuam sendo interpretadas antes dos comandos personalizados.

### Testes automatizados

Testes criados/alterados:

* `test/features/voices/services/custom_command_service_test.dart`
  * normalizacao com acento, pontuacao e espacos duplicados;
  * frase apenas com pontuacao vira vazia;
  * frase reservada e identificada;
  * comando salvo e reconhecido com frase equivalente;
  * comando desativado nao e reconhecido;
  * tipo inexistente vira desconhecido controlado.
* `test/features/voices/controllers/voice_command_controller_test.dart`
  * comando personalizado funciona sem chave da IA;
  * comando global tem prioridade sobre personalizado conflitante.
* `test/features/settings/controllers/settings_controller_test.dart`
  * frase vazia apos normalizacao e rejeitada;
  * frase reservada e rejeitada;
  * duplicata normalizada e rejeitada.
* `test/repositories/settings_custom_command_repository_test.dart`
  * cobertura existente de salvar, listar, filtrar ativos, alternar ativo e excluir foi mantida.

### Teste manual recomendado

1. Rodar app no Android fisico.
2. Fazer login.
3. Abrir Configuracoes.
4. Criar comando personalizado valido, por exemplo `modo palco`, apontando para uma acao do catalogo.
5. Fechar e abrir novamente Configuracoes.
6. Confirmar que o comando aparece salvo.
7. Falar `modo palco`.
8. Confirmar que a acao associada acontece.
9. Tentar criar comando com frase vazia.
10. Confirmar mensagem amigavel.
11. Tentar criar comando reservado, como `voltar` ou `tela inicial`.
12. Confirmar que o app bloqueia.
13. Criar comando duplicado com variacao de espacos ou pontuacao, como `modo   palco!`.
14. Confirmar que o app bloqueia duplicata.
15. Desativar o comando pelo switch.
16. Confirmar que ele nao e mais reconhecido.
17. Remover o comando.
18. Confirmar que ele nao aparece mais na lista.
19. Confirmar que comandos globais como `voltar`, `tela inicial`, `confirmar`, `cancelar`, `gravar` e `sair` continuam funcionando.

### Criterio de aprovacao manual

A etapa so passa se comandos personalizados estiverem coerentes com a funcionalidade real do app: salvar, listar, reconhecer/executar quando aplicavel e proteger comandos reservados sem quebrar comandos globais, comandos locais ou fallback sem Gemini.

## F.13 - Textos tecnicos na UI

### Problema observado

A interface ainda podia expor textos tecnicos em fluxos normais, como estados internos de voz, excecoes concatenadas em mensagens de erro, caminho completo de arquivo e termos de persistencia como banco de dados.

### Diagnostico

Foram confirmados no codigo os seguintes pontos visiveis ao usuario:

* o cabecalho visual de voz do Editor mostrava labels internos como `sleeping`, `listeningCommand` e `processingCommand`;
* `VoiceStatusBar` exibia diretamente a mensagem recebida, sem proteger contra estados internos;
* o Editor mostrava o caminho completo da gravacao atual e das faixas salvas;
* erros em Login, Cadastro, Configuracoes, Projeto Detalhes, Minhas Gravacoes, Detalhes da Gravacao, Historico, Dashboard e controllers de listas podiam concatenar excecoes com `$e`;
* confirmacoes de exclusao de gravacao mencionavam `banco de dados`;
* respostas de falha TTS podiam mencionar erro de banco de dados.

Termos tecnicos restantes em `debugPrint`, diagnostics, services e testes foram classificados como log/codigo interno, nao UI.

### Correcao realizada

* Criado `UserFacingMessages` em `lib/core/ui/user_facing_messages.dart` para centralizar:
  * traducao de estados internos de voz;
  * sanitizacao de erros antes de mostrar ao usuario;
  * exibicao de nome de arquivo sem caminho interno.
* `VoiceStatusBar` passou a mapear estados tecnicos para labels amigaveis.
* O Editor passou a mostrar:
  * `Aguardando comando`;
  * `Ouvindo comando`;
  * `Processando comando`;
  * `Nao consegui concluir a acao`.
* O Editor deixou de mostrar caminhos completos e passou a exibir apenas `Arquivo atual: <nome do arquivo>`.
* Mensagens com excecao crua foram substituidas por frases amigaveis em:
  * Login;
  * Cadastro;
  * Configuracoes;
  * Dashboard;
  * Historico;
  * Meus Projetos / Detalhes do Projeto;
  * Minhas Gravacoes;
  * Detalhes da Gravacao;
  * Editor;
  * controllers de projetos e gravacoes.
* Confirmacoes de exclusao passaram a falar em remover do app e do dispositivo, sem citar banco de dados.
* Falha de TTS para persistencia deixou de mencionar banco de dados.
* `GEMINI_API_KEY` continua fora das mensagens publicas ao usuario.

### Testes automatizados

Testes criados/alterados:

* `test/widgets/core_ui_widget_test.dart`
  * `VoiceStatusBar` traduz `listeningCommand` para `Ouvindo comando`;
  * `UserFacingMessages.error` bloqueia `GEMINI_API_KEY`;
  * `UserFacingMessages.error` bloqueia `PlatformException`;
  * mensagens amigaveis de validacao sao preservadas;
  * caminhos internos exibem somente o nome do arquivo.

### Teste manual recomendado

1. Rodar app no Android fisico.
2. Fazer login.
3. Na Home, observar o status de voz.
4. Dizer comando desconhecido.
5. Confirmar que nao aparece `GEMINI_API_KEY`, `Exception` ou texto tecnico.
6. Abrir Configuracoes.
7. Verificar se textos de controle por voz sao amigaveis.
8. Abrir Editor.
9. Confirmar que o painel de voz nao mostra `sleeping`, `listeningCommand` ou `processingCommand`.
10. Gravar e salvar audio.
11. Confirmar que nao aparece caminho interno de arquivo como mensagem principal.
12. Abrir Minhas Gravacoes.
13. Verificar se os dados sao apresentados de forma amigavel.
14. Abrir detalhes de uma gravacao.
15. Confirmar que erros e confirmacoes nao citam banco de dados, exceptions ou paths tecnicos.
16. Forcar erro simples, se possivel, sem quebrar app.
17. Confirmar que a mensagem e compreensivel para usuario final.

### Criterio de aprovacao manual

A etapa so passa se o usuario final nao vir estados internos, nomes de excecao, API keys, paths tecnicos ou mensagens de debug em fluxos normais.

## F.14 - Ortografia, acentuação e encoding

### Problema observado

A interface ainda tinha textos sem acento, sem cedilha ou com encoding quebrado em mensagens visíveis ao usuário, especialmente em fluxos de voz, gravação, navegação, dashboard, configurações e histórico.

### Diagnóstico

Foram encontrados textos públicos sem acentuação em:

* Home, Login e Cadastro;
* Meus Projetos e Detalhes do Projeto;
* Editor Musical e coordenador de gravação;
* Minhas Gravações e Detalhes da Gravação;
* Dashboard e insights;
* Histórico;
* Configurações;
* `VoiceStatusBar`, mensagens compartilhadas, navegação por voz, scroll por voz e TTS.

Também foi confirmado mojibake no Editor em mensagens como `NÃ£o foi possÃ­vel reconhecer a fala` e `gravaÃ§Ã£o`. As ocorrências em aliases, `tipoComando`, nomes de enums, rotas, owners e chaves internas foram preservadas quando não são texto final de UI.

### Correção realizada

* Corrigidos textos visíveis para português com acentos e cedilha, como `Não foi possível`, `Gravação`, `Configurações`, `Histórico`, `Ação`, `Permissão`, `Reprodução`, `Duração` e `Você`.
* Corrigido mojibake confirmado no Editor.
* Atualizados rótulos de status de gravação para `Concluída` e `Excluída`.
* Atualizados status e mensagens de voz em helpers, mixins, navegação, scroll e TTS.
* Atualizados rótulos de ações executadas em `CommandService` e `AiCommandService`, sem alterar aliases, `tipoComando` ou normalização.
* Mantido suporte a comandos falados sem acento, como `configuracoes`, `gravacoes`, `historico`, `inicio` e `nao`.

### Testes automatizados

Testes criados/alterados:

* `test/widgets/core_ui_widget_test.dart`
  * estados internos de voz continuam mapeados para mensagens amigáveis;
  * mensagem de erro pública usa acentuação correta;
  * textos compartilhados exibem `começar` com acento.
* `test/widgets/recording_status_chip_widget_test.dart`
  * chips exibem `Concluída` e `Excluída`.
* `test/features/home/pages/home_page_test.dart`
  * Home valida títulos e mensagem de modo manual com acentos.
* `test/features/voices/services/command_service_test.dart`
  * comandos sem acento `configuracoes`, `gravacoes`, `historico`, `inicio` e `nao` continuam reconhecidos.
* Testes de navegação, scroll, editor, áudio, dashboard e TTS foram ajustados para as novas mensagens públicas.

### Teste manual recomendado

1. Rodar app no Android físico.
2. Fazer login.
3. Passar pelas telas Home, Meus projetos, Detalhes do projeto, Editor, Minhas gravações, Detalhes da gravação, Dashboard, Histórico e Configurações.
4. Conferir títulos, botões, mensagens, chips, status de voz e modais.
5. Confirmar que não aparecem `Gravacao`, `Configuracoes`, `Historico`, `Nao` ou caracteres quebrados como `Ã` e `�` na UI.
6. Testar comandos falados sem acento: `configuracoes`, `gravacoes`, `historico`, `inicio` e `nao`.
7. Confirmar que os comandos continuam funcionando.

### Critério de aprovação manual

A etapa só passa se a UI estiver em português correto, sem mojibake visível, e se comandos sem acento continuarem funcionando.

## F.15 — Esqueci minha senha

### Problema observado

A tela de Login não oferecia orientação ao usuário que esqueceu a senha.

### Diagnóstico

O app usa autenticação local no dispositivo e também permite entrar com uma conta Google. Como o protótipo não possui backend de recuperação por e-mail, envio de mensagens ou redefinição autenticada de senha, não seria seguro nem correto simular uma recuperação automática.

### Correção realizada

* Adicionado o link `Esqueci minha senha` na tela de Login.
* Criado um diálogo curto com a limitação real da recuperação nesta versão.
* Usuários de conta Google são orientados a usar o botão `Entrar com Google`.
* Usuários de conta local são orientados a criar uma nova conta ou solicitar redefinição ao responsável pelo app.
* O fluxo não solicita e-mail, não promete envio, não altera credenciais e não expõe informações sensíveis ou detalhes técnicos.

### Testes automatizados

Testes criados/alterados em `test/features/voices/pages/login_page_test.dart`:

* o link `Esqueci minha senha` aparece na LoginPage;
* o toque abre o diálogo `Recuperação de senha`;
* a mensagem orienta contas Google e locais sem prometer envio de e-mail;
* a mensagem não contém `SQLite`, `hash`, `salt` ou `banco de dados`;
* o botão `Entendi` fecha o diálogo;
* o fluxo não chama autenticação local ou Google e não navega para a Home;
* os testes existentes de login local, Google Login e navegação permanecem ativos.

### Teste manual recomendado

1. Rodar o app no Android físico.
2. Abrir a tela de Login.
3. Tocar em `Esqueci minha senha`.
4. Confirmar que aparece o diálogo de recuperação.
5. Confirmar que ele não promete envio de e-mail.
6. Confirmar que não mostra termos técnicos como SQLite, hash, salt ou banco de dados.
7. Fechar com `Entendi`.
8. Confirmar que continua na tela de Login.
9. Testar o Login local normal.
10. Testar o botão Google, se configurado.

### Critério de aprovação manual

A etapa só passa se o usuário tiver uma orientação clara e honesta sobre senha esquecida, sem promessa falsa de recuperação automática.

## F.16 — Microcopy de mensagens

### Problema observado

Após a remoção de textos técnicos e a correção de ortografia, algumas mensagens públicas ainda estavam corretas, mas genéricas ou pouco orientativas para uma apresentação de TCC.

### Diagnóstico

Foram revisadas mensagens visíveis em SnackBars, status de voz, resultados de comandos, validações de formulário, estados vazios, login/cadastro, projetos, gravações, editor, configurações e comandos personalizados. Os principais pontos encontrados foram:

* mensagens genéricas em `UserFacingMessages`, como falha de ação, carregamento, salvamento, reprodução e gravação;
* comando desconhecido e comando indisponível sem exemplos claros;
* mensagens de login/cadastro que não orientavam o próximo passo;
* estados vazios de projetos, gravações, faixas e comandos sem orientação suficiente;
* mensagens de sucesso ou remoção pouco específicas;
* alguns textos finais ainda sem acentuação, como `excluido`, `Descricao` e `nao disponivel`.

### Correção realizada

* Melhoradas mensagens centralizadas em `lib/core/ui/user_facing_messages.dart`.
* O comando desconhecido passou a sugerir exemplos úteis: `meus projetos`, `minhas gravações` e `configurações`.
* Comandos reconhecidos, mas indisponíveis na tela atual, passaram a explicar a indisponibilidade.
* Login e cadastro ganharam mensagens mais orientativas para senha, credenciais inválidas, conta já existente e falhas de criação.
* Projetos e gravações passaram a usar mensagens específicas para criação, remoção, busca vazia, reprodução e erros.
* Configurações e comandos personalizados passaram a orientar melhor frases reservadas, duplicadas, salvamento e lista vazia.
* Editor e scroll por voz passaram a orientar melhor comandos desconhecidos, lista ausente, fim da lista e falta de gravações.

Exemplos de antes/depois:

* Antes: `Comando não reconhecido.`
  Depois: `Não entendi o comando. Tente dizer: meus projetos, minhas gravações ou configurações.`
* Antes: `Comando nao disponivel nesta tela.`
  Depois: `Esse comando não está disponível nesta tela.`
* Antes: `E-mail ou senha incorretos.`
  Depois: `Não foi possível entrar. Confira o e-mail e a senha.`
* Antes: `Este e-mail já está cadastrado.`
  Depois: `Essa conta já existe. Tente entrar ou use outro e-mail.`
* Antes: `Nenhuma gravação encontrada`
  Depois: `Suas gravações aparecerão aqui. Abra o editor para registrar a primeira ideia.`

### Testes automatizados

Testes criados/alterados:

* `test/features/voices/coordination/voice_command_dispatcher_test.dart`
  * comando desconhecido sugere comandos úteis e não mostra termos técnicos;
  * comando reconhecido fora da tela explica indisponibilidade.
* `test/features/voices/controllers/voice_command_controller_test.dart`
  * reforça que a mensagem de comando desconhecido é amigável e contém exemplos.
* `test/features/voices/coordination/voice_scroll_handler_test.dart`
  * reforça mensagem para fim da lista.
* `test/widgets/core_ui_widget_test.dart`
  * valida mensagens compartilhadas específicas e sem termos técnicos.
* `test/features/voices/pages/login_page_test.dart`, `test/features/voices/pages/cadastro_page_test.dart` e `test/widgets/auth_pages_widget_test.dart`
  * atualizados para as novas mensagens de login, senha e cadastro.
* `test/features/settings/controllers/settings_controller_test.dart`
  * atualizado para a nova mensagem de comando personalizado duplicado.

### Teste manual recomendado

1. Rodar o app no Android físico.
2. Fazer login.
3. Dizer um comando desconhecido.
4. Confirmar que a mensagem sugere comandos úteis.
5. Criar projeto e conferir mensagem de sucesso.
6. Criar/gravar áudio e conferir mensagem de sucesso.
7. Abrir lista vazia, se possível, e conferir mensagem orientativa.
8. Tentar ação inválida em configurações/comandos personalizados.
9. Confirmar que a mensagem explica o problema e o próximo passo.
10. Confirmar que não aparecem termos técnicos.

### Critério de aprovação manual

A etapa só passa se as principais mensagens públicas forem claras, úteis e consistentes, sem parecer log técnico ou resposta genérica.

## F.17 — Acessibilidade mínima e feedback visual

### Problema observado

Alguns controles baseados apenas em ícones e o status do controle por voz ainda precisavam de descrições mais claras para leitores de tela e para o uso com toque prolongado. Também era necessário confirmar que os estados principais de voz, gravação e reprodução estavam visíveis e compreensíveis.

### Diagnóstico

A auditoria das telas principais identificou:

* botões de mostrar ou ocultar senha sem tooltip;
* ícones de reproduzir ou parar gravações sem descrição contextual;
* menus de ações de gravações sem indicar a qual item pertencem;
* `VoiceStatusBar` com texto visual amigável, mas sem região semântica ao vivo;
* reprodução de faixas no Editor com botão de ícone sem tooltip.

Os campos de Login e Cadastro já possuíam labels, os botões com texto já tinham área de toque adequada, os switches de Configurações já tinham títulos e descrições, e o Editor já exibia estados como `Gravando`, `Pausado`, `Reproduzindo`, `Processando comando` e a pausa da escuta durante a gravação.

### Correção realizada

* Login e Cadastro receberam tooltips dinâmicos `Mostrar senha` e `Ocultar senha`.
* `VoiceStatusBar` passou a expor uma região semântica ao vivo com o status amigável atual.
* Minhas Gravações e Detalhes do Projeto receberam tooltips contextuais para reproduzir, parar e abrir ações de cada gravação.
* O botão de reprodução de faixa no Editor passou a identificar a gravação que será reproduzida.
* Foram preservados os feedbacks visuais existentes de voz, processamento, gravação, pausa e reprodução, sem redesign ou alteração de regra de negócio.

### Testes automatizados

Testes criados ou reforçados:

* `test/widgets/core_ui_widget_test.dart`
  * valida o label semântico amigável do `VoiceStatusBar`.
* `test/features/voices/pages/login_page_test.dart`
  * valida os tooltips `Mostrar senha` e `Ocultar senha`.
* `test/features/voices/pages/cadastro_page_test.dart`
  * valida os tooltips `Mostrar senha` e `Ocultar senha`.
* A suíte existente continua cobrindo os estados visuais do Editor, os fluxos de gravação e reprodução, as configurações e os comandos sem acento.

### Teste manual recomendado

1. Rodar o app no Android físico.
2. Fazer login.
3. Conferir no Login e Cadastro os campos, o botão de mostrar ou ocultar senha e o link `Esqueci minha senha`.
4. Na Home, conferir o status visível do controle por voz.
5. Em Projetos, conferir as ações de criar, abrir e excluir projeto.
6. No Editor, conferir gravar, pausar, retomar, encerrar e reproduzir, observando os estados visuais.
7. Em Minhas Gravações, conferir reproduzir, parar, abrir detalhes e excluir.
8. Em Configurações, conferir os switches e os comandos personalizados.
9. Ativar o TalkBack, se possível, e navegar pelos botões principais.
10. Confirmar que os controles têm descrições compreensíveis e que o status de voz é anunciado quando muda.

### Critério de aprovação manual

A etapa só passa se as ações principais tiverem labels ou tooltips claros e se os estados de voz, gravação e reprodução forem compreensíveis visualmente e por leitor de tela.

## F.18 — Regressão automatizada final

### Objetivo

Validar automaticamente as correções F.1 a F.17 antes da geração do APK final e do segundo teste físico, verificando regressões, cobertura dos fluxos críticos, testes desabilitados, arquivos gerados e possíveis dados sensíveis.

### Validações executadas

* `dart analyze`;
* `flutter test --reporter compact`;
* `flutter test --coverage`;
* `flutter build apk --debug`;
* busca por `skip`, `@Skip`, `only`, `solo` e marcadores de testes temporariamente desabilitados;
* busca segura por chaves, tokens, autorizações, senhas literais, arquivos `.env`, keystores e outros arquivos sensíveis;
* conferência de `build/`, `coverage/` e `.dart_tool/`;
* revisão dos testes existentes para os fluxos críticos corrigidos entre F.1 e F.17.

### Resultado

* `dart analyze`: concluído sem issues.
* `flutter test --reporter compact`: 473 testes aprovados.
* `flutter test --coverage`: 473 testes aprovados e cobertura gerada apenas localmente em `coverage/`.
* `flutter build apk --debug`: concluído com geração de `build/app/outputs/flutter-apk/app-debug.apk`.
* Nenhum teste com `skip`, `@Skip`, `only`, `solo` ou marcador de desativação foi encontrado.
* Nenhuma nova chave Gemini, autorização fixa, bearer token, senha em texto puro, `.env`, keystore ou arquivo `.jks` foi encontrado.
* `build/`, `coverage/` e `.dart_tool/` permanecem ignorados pelo Git.
* O relatório gerado `android/build/reports/problems/problems-report.html`, rastreado por commits antigos, foi removido do versionamento; a regra existente para `build/` impede que seja adicionado novamente.

### Cobertura por fluxo

* Login: login local, Google Login, sucesso, cancelamento, erros amigáveis, recuperação de senha e limpeza da pilha.
* Player: conclusão natural, nova reprodução após conclusão, parada, falhas e liberação de estado.
* Navegação: login e logout limpam a pilha, retorno seguro e Home sem duplicação.
* Voz e comandos: fallback sem Gemini, aliases com e sem acento, comandos globais, comando desconhecido amigável, scroll e comandos personalizados.
* Ciclo de vida: retomada em `didPopNext`, remoção de listeners no `dispose` e prevenção de assinaturas ou execuções duplicadas.
* Confirmação: confirmação e cancelamento por voz; `sim` sem modal pendente não executa ação destrutiva.
* Editor: bloqueio de navegação insegura durante gravação, confirmação para sair e restauração do estado de playback.
* UI: remoção de textos técnicos, acentuação, microcopy, labels, tooltips e semântica do status de voz.

### Riscos remanescentes

* A validação em aparelho Android físico continua necessária.
* Google Login ainda depende dos SHA-1 e SHA-256 corretos para o ambiente de build.
* STT, permissões e concorrência de microfone dependem do comportamento do aparelho real.
* TalkBack e a ordem prática de foco precisam de validação física.
* Durante a gravação, os comandos por voz continuam limitados pela disputa de microfone no Android, conforme documentado na F.9.
* A cobertura gerada confirma a execução instrumentada, mas não substitui os testes físicos de áudio, Google e acessibilidade.

### Próximo passo

F.19 — APK debug final e teste físico 2.

## F.19 — APK debug final e teste físico 2

### APK gerado

* Branch: `fix/qa-fisico-correcoes`.
* Commit usado no APK: `be94291`.
* Comando usado: `flutter build apk --debug`.
* Caminho do APK: `build\app\outputs\flutter-apk\app-debug.apk`.
* Resultado do build: concluído com sucesso.
* Tamanho do APK: 175.873.196 bytes.
* Data/hora de geração: 13/06/2026 01:35:54.
* O APK fica em `build/`, que é ignorado pelo Git, e não deve ser commitado.

### Roteiro de Teste Físico 2

#### 1. Abertura e autenticação

* Abrir o app no Android físico.
* Testar login local com credenciais válidas.
* Testar erro de login com senha errada.
* Tocar em `Esqueci minha senha` e validar a orientação honesta.
* Testar Google Login se o SHA-1/SHA-256 debug estiver configurado.
* Confirmar que Login e Cadastro não aparecem ao voltar da Home, exceto após logout.

#### 2. Navegação autenticada

* Navegar da Home para Meus projetos.
* Navegar da Home para Minhas gravações.
* Navegar da Home para Dashboard.
* Navegar da Home para Histórico.
* Navegar da Home para Configurações.
* Voltar por AppBar.
* Voltar pelo botão Android.
* Confirmar que o app não cai no Login durante a navegação autenticada.

#### 3. Comandos globais por voz

Testar:

* `meus projetos`;
* `minhas gravações`;
* `dashboard`;
* `histórico`;
* `configurações`;
* `tela inicial`;
* `voltar`;
* `voltar para tela inicial`.

Confirmar:

* comandos funcionam fora da Home;
* `voltar` volta uma tela;
* `tela inicial` vai direto para Home;
* nenhum comando mostra `GEMINI_API_KEY`.

#### 4. Aliases naturais

Testar:

* `abre configurações`;
* `vai para projetos`;
* `mostrar gravações`;
* `ver indicadores`;
* `meu painel`;
* `preferências`;
* `home`;
* `início`.

Confirmar que todos funcionam conforme esperado.

#### 5. Projetos

* Criar projeto.
* Abrir projeto.
* Editar ou renomear, se a ação estiver disponível.
* Excluir projeto.
* Cancelar exclusão por voz.
* Confirmar exclusão por voz.
* Validar mensagens amigáveis.

#### 6. Editor Musical

* Abrir o editor.
* Iniciar gravação por toque.
* Iniciar gravação por voz, se disponível antes da gravação.
* Pausar e retomar, se disponível.
* Encerrar e salvar gravação.
* Tentar sair durante gravação.
* Cancelar a saída.
* Confirmar saída segura.
* Confirmar que o app não perde áudio sem confirmação.

Observação: durante gravação ativa, comandos por voz podem estar limitados por disputa real do microfone no Android. Validar que o app informa ou bloqueia com segurança.

#### 7. Player e gravações

* Abrir Minhas gravações.
* Reproduzir uma gravação.
* Esperar a reprodução terminar.
* Reproduzir novamente a mesma gravação.
* Repetir a reprodução 3 vezes.
* Testar parar e reproduzir novamente.
* Excluir gravação com cancelamento.
* Excluir gravação com confirmação.
* Confirmar que o app não trava.

#### 8. Scroll por voz

Em listas com itens suficientes, testar:

* `descer`;
* `subir`;
* `ir para o fim`;
* `ir para o topo`;
* confirmar que `voltar` não rola;
* confirmar que `tela inicial` não vai para o topo da lista, e sim para Home.

#### 9. Comandos personalizados

* Criar comando personalizado válido.
* Tentar criar comando vazio.
* Tentar criar comando reservado, como `voltar`.
* Tentar duplicado com variação de acento ou espaço.
* Falar o comando personalizado.
* Desativar ou remover o comando.
* Confirmar que ele não é reconhecido após desativar ou remover.

#### 10. Confirmações por voz

Testar em modais:

* dizer `cancelar`;
* dizer `não`;
* dizer `confirmar`;
* dizer `confirmar exclusão`;
* dizer `sim` fora de modal e confirmar que nada destrutivo acontece.

#### 11. Textos, microcopy e ortografia

Conferir:

* sem `GEMINI_API_KEY` na UI;
* sem `PlatformException`;
* sem paths completos;
* sem `sleeping` ou `listeningCommand`;
* sem `Gravacao`, `Configuracoes`, `Historico` ou `Nao` na UI;
* sem caracteres quebrados como `Ã` ou `�`;
* mensagens úteis e claras.

#### 12. Acessibilidade mínima

* Conferir tooltips e labels principais.
* Se possível, ativar TalkBack.
* Conferir status de voz.
* Conferir botão mostrar ou ocultar senha.
* Conferir botões de play, excluir e menu.

#### 13. Estabilidade geral

* Fechar e abrir o app.
* Navegar por várias telas.
* Alternar entre voz e toque.
* Testar sem internet, exceto Google Login.
* Verificar se o app não fecha inesperadamente.

### Comandos úteis para instalação

* Ver dispositivos Flutter: `flutter devices`.
* Ver dispositivos ADB: `adb devices`.
* Rodar direto no aparelho: `flutter run -d <androidDeviceId>`.
* Instalar APK manualmente: `adb install -r build\app\outputs\flutter-apk\app-debug.apk`.

Se houver mais de um dispositivo, registrar o `deviceId` usado. Se o Google Login falhar no aparelho, verificar se os SHA-1 e SHA-256 debug do ambiente atual estão cadastrados no Firebase ou Google Cloud, sem expor chaves no relatório.

### Evidências para salvar

O testador deve guardar:

* prints das telas principais;
* print do APK ou terminal de build;
* print dos testes passando, se necessário;
* lista de bugs encontrados;
* vídeos curtos dos fluxos críticos:
  * Login;
  * comandos por voz;
  * gravação;
  * replay da gravação;
  * confirmação por voz;
  * scroll por voz.

### Resultado do teste físico

* Data:
* Aparelho:
* Android:
* APK/commit:
* Testador:
* Resultado geral:
* Bugs encontrados:
* Bugs bloqueantes:
* Observações:
* Aprovado para banca? Sim/Não

## G.1 — Ajuda rápida de comandos por voz

### Objetivo

Adicionar uma ajuda visual dentro do app para que o usuário saiba quais comandos pode falar, reduzindo dúvidas durante o teste físico e a apresentação para banca.

### Correção realizada

* Criado o widget reutilizável `VoiceCommandHelpDialog`.
* Adicionado o botão `Ver comandos de voz` no bloco principal da Home.
* O botão abre um diálogo com título claro, conteúdo rolável e ação `Fechar`.
* A ajuda lista comandos por categoria:
  * Navegação;
  * Gravação;
  * Reprodução;
  * Listas;
  * Confirmações;
  * Comandos personalizados.
* O texto informa que variações naturais também funcionam, como `abre configurações` e `vai para projetos`.
* A ajuda não executa comandos, não usa microfone, não depende de Gemini e não altera o reconhecimento existente.
* O conteúdo evita termos técnicos como parser, intent, NLU, API, Gemini e CommandService.

### Testes automatizados

Testes criados ou alterados:

* `test/features/voices/widgets/voice_command_help_dialog_test.dart`
  * valida título, categorias e comandos principais;
  * confirma que termos técnicos não aparecem.
* `test/features/home/pages/home_page_test.dart`
  * valida que o botão `Ver comandos de voz` aparece na Home;
  * valida abertura e fechamento do diálogo de ajuda.

### Teste manual recomendado

1. Rodar o app no Android físico.
2. Fazer login.
3. Na Home, tocar em `Ver comandos de voz`.
4. Confirmar que a ajuda abre.
5. Conferir comandos de navegação, gravação, reprodução, listas e confirmação.
6. Fechar a ajuda com `Fechar`.
7. Testar um comando exibido, como `Meus projetos`.
8. Confirmar que o comando funciona.
9. Abrir Configurações e confirmar que comandos personalizados continuam disponíveis.
10. Confirmar que não aparecem termos técnicos.

## G.2 — Ajuda contextual de comandos por tela

### Objetivo

Evoluir a ajuda de comandos por voz para mostrar exemplos úteis conforme a tela atual, deixando a orientação mais clara para o usuário e para a banca sem alterar o reconhecimento real dos comandos.

### Implementação

* O `VoiceCommandHelpDialog` passou a aceitar contextos de ajuda.
* Foram criados contextos para:
  * Home;
  * Projetos;
  * Gravações;
  * Editor;
  * Configurações;
  * ajuda geral.
* A Home continua com o botão `Ver comandos de voz`, agora focado em navegação.
* O Editor ganhou um botão de ajuda no AppBar com comandos de gravação, reprodução e navegação.
* Configurações ganhou um botão de ajuda no AppBar com comandos de tema, controle por voz e comandos personalizados.
* O Editor exibe o aviso: durante uma gravação, alguns comandos podem ficar indisponíveis porque o microfone está sendo usado para gravar.
* A ajuda continua sem executar comandos, sem acessar microfone, sem depender de Gemini e sem alterar parser, aliases ou lógica de voz.
* Os textos evitam termos técnicos como parser, intent, CommandService, NLU, Gemini, API, fallback e handler.

### Testes automatizados

Testes criados ou alterados:

* `test/features/voices/widgets/voice_command_help_dialog_test.dart`
  * valida o contexto Home com comandos de navegação;
  * valida o contexto Projetos com `Novo projeto` e comandos de lista;
  * valida o contexto Gravações com `Tocar` e `Excluir gravação`;
  * valida o contexto Editor com `Gravar` e o aviso sobre microfone;
  * valida o contexto Configurações com `Modo escuro` e `Controle por voz`;
  * confirma que os contextos não exibem termos técnicos.
* `test/features/home/pages/home_page_test.dart`
  * valida que o botão da Home continua abrindo e fechando a ajuda.

### Teste manual recomendado

1. Rodar o app no Android físico.
2. Fazer login.
3. Na Home, abrir ajuda de comandos.
4. Confirmar comandos gerais de navegação.
5. Abrir Meus Projetos e validar os comandos de projeto e lista na ajuda, se o botão for adicionado em etapa posterior.
6. Abrir Minhas Gravações e validar comandos de reprodução e lista na ajuda, se o botão for adicionado em etapa posterior.
7. Abrir Editor e abrir ajuda.
8. Confirmar comandos de gravação e aviso sobre microfone.
9. Abrir Configurações e abrir ajuda.
10. Confirmar comandos de tema, voz e comandos personalizados.
11. Confirmar que nenhum diálogo mostra termos técnicos.

## G.3 — Ajuda contextual em Projetos e Gravações

### Objetivo

Expor a ajuda contextual também nas telas de Meus Projetos e Minhas Gravações, usando o componente já criado nas etapas G.1 e G.2 sem alterar reconhecimento de comandos.

### Implementação

* Adicionado botão de ajuda na AppBar de Meus Projetos.
* Adicionado botão de ajuda na AppBar de Minhas Gravações.
* Meus Projetos abre `VoiceCommandHelpContext.projects`.
* Minhas Gravações abre `VoiceCommandHelpContext.recordings`.
* Os botões usam tooltip `Comandos desta tela`.
* Nenhum parser, alias, comando, scroll, player, exclusão ou persistência foi alterado.

### Testes automatizados

Testes criados:

* `test/features/projects/pages/meus_projetos_page_test.dart`
  * valida que o botão aparece;
  * abre o diálogo `Comandos em projetos`;
  * confere `Novo projeto` e `Descer`;
  * fecha o diálogo.
* `test/features/recordings/pages/minhas_gravacoes_page_test.dart`
  * valida que o botão aparece;
  * abre o diálogo `Comandos em gravações`;
  * confere `Tocar` e `Excluir gravação`;
  * fecha o diálogo.

### Teste manual recomendado

1. Rodar app no Android físico.
2. Fazer login.
3. Abrir Meus Projetos.
4. Tocar no botão de ajuda.
5. Conferir comandos de projeto e lista.
6. Fechar ajuda.
7. Abrir Minhas Gravações.
8. Tocar no botão de ajuda.
9. Conferir comandos de reprodução, exclusão, confirmação e lista.
10. Confirmar que não aparecem termos técnicos.
11. Confirmar que os comandos reais continuam funcionando.

## H.1 — Correção da estabilidade da escuta por voz após navegação

### Bugs corrigidos

* Escuta desabilitada após voltar por AppBar.
* Escuta desabilitada após usar o botão Android para voltar.
* Comando executado antes de a frase terminar.
* `iniciar gravação` podendo virar navegação incorreta.
* Erro repetitivo de reconhecimento de voz.

### Diagnóstico técnico

* A tela anterior recebia `didPopNext`, mas podia tentar retomar a escuta antes
  de a pausa assíncrona iniciada em `didPushNext` terminar. Nesse caso, o estado
  ainda indicava escuta ativa, a retomada era ignorada e a pausa concluía logo
  depois, deixando a tela sem voz.
* O `SpeechService` aceitava resultados parciais após um debounce de 450 ms.
  Uma pausa natural entre `reproduzir` e `gravação 2` era suficiente para
  executar o texto incompleto.
* O Editor tinha coordenação própria de microfone, mas não era `RouteAware`.
  Ao abrir outra tela, a escuta era cancelada pelo observador global e não havia
  retomada equivalente ao voltar.
* O parser já reconhecia `iniciar gravação` corretamente. A navegação incorreta
  ocorria porque o parcial `início` podia ser entregue antes da frase completa
  e era interpretado como retorno à tela inicial.
* Cada falha do STT atualizava novamente o estado de erro e podia agendar outra
  recuperação, fazendo a mesma mensagem reaparecer em sequência.

### Correção realizada

* A retomada contextual agora aguarda a pausa da rota coberta terminar antes de
  solicitar nova escuta.
* Foi adicionado um guarda contra solicitações simultâneas de retomada.
* O Editor passou a observar o ciclo de rotas, pausar ao ser coberto e retomar
  ao voltar somente quando voz contínua está ativa e não há gravação usando o
  microfone.
* Resultados parciais continuam sendo acumulados, mas só são despachados quando
  o STT informa resultado final. Como fallback de plataforma, o último parcial
  só é aceito quando a sessão termina com `done` ou `notListening`.
* Comandos finais repetidos em intervalo curto são executados uma única vez.
* Comandos de gravar, pausar, retomar e encerrar são priorizados no Editor antes
  da navegação global.
* Erros de reconhecimento usam cooldown, fazem uma única tentativa segura de
  recuperação por ciclo e exibem a mensagem amigável:
  `Não consegui ouvir o comando agora. Tente novamente em alguns segundos.`

### Testes automatizados

Testes criados ou alterados:

* `test/features/voices/services/speech_service_test.dart`
  * parcial `reproduzir` não executa;
  * final `reproduzir gravação 2` executa uma vez;
  * duplicidade próxima é ignorada;
  * término da sessão estabiliza o último parcial quando necessário.
* `test/features/voices/services/voice_recognition_error_guard_test.dart`
  * erros dentro do cooldown não repetem mensagem nem recuperação;
  * erro pode ser informado novamente depois do cooldown;
  * mensagem pública não contém termo técnico.
* `test/features/voices/coordination/contextual_voice_listening_mixin_test.dart`
  * retorno aguarda a pausa assíncrona;
  * retorno por navegação e botão Android solicita retomada uma vez;
  * assinatura de rota não duplica;
  * `dispose` libera o owner.
* `test/features/editor/pages/editor_voice_flow_policy_test.dart`
  * `iniciar gravação` é classificado como gravação e não como voltar;
  * `voltar` continua separado e sujeito à política segura do Editor.

### Teste manual recomendado

1. Rodar app no Android físico.
2. Fazer login.
3. Abrir Meus Projetos.
4. Voltar pela AppBar.
5. Confirmar que a Home ainda escuta comandos.
6. Abrir Minhas Gravações.
7. Voltar pelo botão Android.
8. Confirmar que a Home ainda escuta comandos.
9. Abrir Minhas Gravações.
10. Falar `reproduzir gravação 2`.
11. Confirmar que o app não executa antes da frase terminar.
12. Abrir Editor.
13. Falar `iniciar gravação`.
14. Confirmar que grava em vez de voltar tela.
15. Verificar se a mensagem de erro de reconhecimento não fica repetindo em
    loop.

## H.2 — Correção do player de gravações

### Bugs corrigidos

* Botão play/stop não atualizava na primeira reprodução.
* Gravação podia entrar em loop ou não finalizar corretamente.
* Comando `reproduzir gravação 2` não selecionava corretamente a gravação.
* Comando ambíguo tocava automaticamente a gravação mais recente ou a primeira
  da lista.

### Diagnóstico técnico

* A tela Minhas Gravações usa `RecordingsListController`, que delega a execução
  para `AudioPlayerService`.
* `AudioPlayerService.play()` aguardava o `just_audio.play()`. No `just_audio`,
  esse `Future` pode terminar apenas quando a reprodução para ou completa. Com
  isso, o controller só atualizava `playingRecordingId` no fim do áudio, e o
  botão continuava como play durante a primeira execução.
* A lista limpava o estado em qualquer evento `!state.playing`. Isso podia
  confundir transições intermediárias do player com conclusão real.
* O modo de loop não era explicitamente desligado ao preparar o arquivo.
* O comando por voz buscava por nome e, quando não encontrava parâmetro, caía no
  primeiro item da lista. Assim `reproduzir gravação` com várias opções era
  perigoso, e `reproduzir gravação 2` podia não ser tratado como posição.

### Correção realizada

* O adapter do `just_audio` agora inicia a reprodução sem bloquear a UI até o
  fim do áudio.
* O `AudioPlayerService` força `LoopMode.off` ao preparar um arquivo.
* A conclusão natural usa `ProcessingState.completed` para limpar o estado,
  voltar o botão para play e reposicionar o áudio no início.
* Ao trocar de gravação, o controller para a anterior antes de tocar a nova.
* O controller resolve comandos por número ou ordem da lista visível:
  `1`, `2`, `primeira`, `segunda`, etc.
* Com uma única gravação, `reproduzir gravação` toca a única opção.
* Com várias gravações, `reproduzir gravação` pede especificação:
  `Diga qual gravação deseja tocar, por exemplo: reproduzir gravação 1.`
* Número fora da lista retorna:
  `Não encontrei essa gravação na lista.`

### Testes automatizados

Testes criados ou alterados:

* `test/features/editor/services/audio_player_service_test.dart`
  * valida início imediato do playback;
  * valida `LoopMode.off`;
  * valida conclusão natural, retorno ao início e replay;
  * valida falhas de start sem manter sessão presa.
* `test/features/recordings/controllers/recordings_list_controller_test.dart`
  * play muda estado para parar;
  * stop volta para play;
  * conclusão limpa estado sem reiniciar;
  * replay manual funciona;
  * trocar gravação para a anterior e toca a nova;
  * comando por número e ordem seleciona o item correto;
  * comando ambíguo com várias gravações não toca automaticamente;
  * comando ambíguo com uma gravação toca a única;
  * número inexistente mostra mensagem amigável.
* `test/features/voices/services/command_service_test.dart`
  * reconhece `reproduzir gravação 1`;
  * reconhece `tocar gravação 2`;
  * reconhece `dar play na gravação 1`;
  * reconhece `tocar a segunda gravação`, `reproduzir a segunda` e
    `tocar a primeira`.
* `test/features/recordings/pages/minhas_gravacoes_page_test.dart`
  * mantém o teste de ajuda contextual com o stream tipado do player.

### Teste manual recomendado

1. Rodar app no Android físico.
2. Fazer login.
3. Abrir Minhas Gravações.
4. Tocar no play de uma gravação.
5. Confirmar que o botão muda para parar imediatamente.
6. Esperar a gravação terminar.
7. Confirmar que o botão volta para play.
8. Confirmar que o áudio não toca em loop.
9. Reproduzir a mesma gravação novamente.
10. Repetir 3 vezes.
11. Falar `reproduzir gravação 1`.
12. Confirmar que toca a primeira gravação.
13. Falar `reproduzir gravação 2`.
14. Confirmar que toca a segunda gravação.
15. Falar `reproduzir gravação` com várias gravações.
16. Confirmar que o app pede para especificar qual gravação.
17. Parar reprodução e reproduzir novamente.

## H.3 — Correção de comandos personalizados

### Bug corrigido

* Comandos personalizados eram criados e listados em Configurações, mas podiam
  não ser reconhecidos corretamente ao serem falados depois.

### Diagnóstico técnico

* A criação já salvava `frase`, `tipo_comando`, `ativo`, `usuario_id` e
  `data_criacao` sem exigir mudança de banco.
* A validação de frase vazia, reservada e duplicada já usava normalização por
  acento, maiúsculas/minúsculas, pontuação e espaços duplicados.
* O fluxo de voz já chamava o parser local primeiro, depois comandos
  personalizados do usuário e só então o fallback de IA/mensagem de não
  reconhecido.
* A falha estava no contrato do resultado personalizado: ele era convertido para
  um `tipoComando` sintético, como `personalizado_abrir_editor`, em vez de manter
  o tipo real da ação (`abrir_editor`). Isso deixava o reconhecimento menos
  consistente para registro, execução e diagnósticos do fluxo real.
* Os testes existentes cobriam criação/listagem e um reconhecimento básico, mas
  não cobriam criação seguida de execução, outro usuário, comando removido e
  ordem custom antes da IA configurada.

### Correção realizada

* Comandos personalizados reconhecidos agora mantêm o `tipoComando` real da ação
  selecionada pelo usuário.
* A normalização continua aceitando variações de acento, maiúsculas/minúsculas,
  pontuação simples e espaços duplicados.
* A consulta continua restrita ao `usuario_id` da sessão e somente a comandos
  ativos.
* Comando local/reservado continua tendo prioridade sobre personalizado.
* Se não houver comando personalizado ativo compatível, o app segue o fallback
  existente de IA configurada ou mensagem amigável de comando não reconhecido.

### Testes automatizados

Testes criados ou alterados:

* `test/features/voices/services/custom_command_service_test.dart`
  * comando personalizado ativo é encontrado por frase exata;
  * comando ativo é encontrado sem acento e com espaços extras;
  * comando inativo não é encontrado;
  * comando removido não é encontrado;
  * comando de outro usuário não é encontrado;
  * tipo inválido continua virando desconhecido controlado.
* `test/features/voices/controllers/voice_command_controller_test.dart`
  * comando personalizado funciona sem chave da IA;
  * comando personalizado é consultado antes da IA configurada;
  * ausência de comando personalizado segue fallback de não reconhecido;
  * comando local/global continua tendo prioridade sobre personalizado conflitante.
* `test/features/settings/controllers/settings_controller_test.dart`
  * comando criado pelo usuário pode ser reconhecido depois na execução;
  * comando desativado ou removido deixa de executar.

### Teste manual recomendado

1. Rodar app no Android físico.
2. Fazer login.
3. Abrir Configurações.
4. Criar comando personalizado válido.
5. Falar o comando criado.
6. Confirmar que o app reconhece e executa a ação esperada.
7. Testar a mesma frase com diferença de acento ou maiúscula.
8. Desativar o comando.
9. Falar novamente e confirmar que não executa.
10. Ativar novamente, se disponível.
11. Remover o comando.
12. Falar novamente e confirmar que não executa.
13. Confirmar que comandos locais como `voltar` e `tela inicial` continuam
    funcionando.

## H.4 - Persistencia de sessao local

### Bug corrigido

* A sessao autenticada nao era restaurada ao reiniciar o app. Mesmo com usuario
  local valido no SQLite, a inicializacao abria diretamente o Login.

### Diagnostico tecnico

* O app iniciava em `LoginPage` a cada execucao, sem uma etapa de bootstrap de
  autenticacao.
* O login local e o login Google retornavam um `Usuario`, mas nao havia um
  marcador persistido da sessao atual.
* O logout ja centralizava limpeza de voz, runtime e Google Sign-In em
  `AuthSessionService`, mas nao limpava nenhuma sessao local persistida.
* Persistir o objeto `Usuario` inteiro seria incorreto, porque poderia gravar
  `senha_hash`, salt, metadados de credencial ou dados externos desnecessarios.

### Correcao realizada

* Criado `AuthGate` para decidir a tela inicial entre Login e Home.
* Criado `AuthStartupService` para restaurar a sessao persistida antes de abrir
  a interface autenticada.
* `main.dart` passou a iniciar em `AuthGate`.
* `AuthSessionService` passou a persistir somente o `usuario_id` local em
  `auth_session_user_id.txt`, no diretorio de suporte da aplicacao.
* `AuthSessionService.restoreAuthenticatedUser()` valida o id persistido usando
  `UsuarioRepository.buscarPorId`.
* Sessao ausente, id invalido, id menor ou igual a zero e usuario inexistente
  sao tratados como nao autenticados; quando ha arquivo invalido, ele e limpo.
* `AuthService.autenticarUsuario()` salva a sessao local apos login local valido.
* `AuthService.entrarComGoogle()` tambem salva a sessao local apos resolver o
  usuario local.
* `AuthSessionService.logout()` passou a limpar a sessao persistida antes de
  sair do Google.

### Dados persistidos

* Somente o `usuario_id` local, em texto simples, no arquivo
  `auth_session_user_id.txt`.

### Dados nao persistidos na sessao

* Senha em texto claro.
* `senha_hash`.
* `senha_salt`.
* Token Google.
* API key do Gemini.
* Dados completos do usuario.

### Testes automatizados

Testes criados ou alterados:

* `test/features/voices/services/auth_session_service_test.dart`
  * salva sessao com `usuario_id`;
  * restaura usuario valido;
  * remove sessao invalida;
  * nao cria sessao para usuario sem id;
  * logout limpa sessao persistida;
  * logout continua tentando Google Sign-Out mesmo se a limpeza local falhar.
* `test/features/voices/services/auth_startup_service_test.dart`
  * sem sessao abre fluxo nao autenticado;
  * sessao valida abre fluxo autenticado;
  * sessao para usuario inexistente e limpa e volta ao Login.
* `test/features/voices/services/auth_service_test.dart`
  * login local valido salva sessao;
  * credencial local invalida nao salva sessao;
  * login Google valido salva sessao.
* `test/features/voices/pages/login_page_test.dart`
  * login local e Google continuam navegando para Home e salvando sessao.
* `test/features/home/pages/home_page_test.dart`
  * logout confirmado limpa sessao e remove Home da pilha.
* `test/repositories/usuario_repository_test.dart`
  * busca por id restaura usuario local valido e retorna null para inexistente.

### Validacoes executadas

```text
dart analyze
No issues found!

flutter test --reporter compact
00:25 +521: All tests passed!

flutter build apk --debug
Built build\app\outputs\flutter-apk\app-debug.apk

git diff --check
Sem erros; apenas avisos esperados de LF/CRLF no Windows.
```

### Teste manual recomendado

1. Rodar app no Android fisico.
2. Fazer login local.
3. Fechar totalmente o app.
4. Abrir novamente.
5. Confirmar que a Home abre sem pedir novo login.
6. Fazer logout.
7. Fechar e abrir novamente.
8. Confirmar que o Login abre.
9. Repetir com Google Login, se configurado.

## H.5 - Feedback e seguranca no Google Login

### Bug corrigido

* No teste fisico, ao tentar entrar ou cadastrar com Google, o app podia voltar
  para a tela sem feedback claro. O usuario nao sabia se cancelou, se houve
  falha de conexao, problema de configuracao do app ou erro interno ao preparar
  a conta local.

### Diagnostico tecnico

* `LoginPage` e `CadastroPage` ja bloqueavam clique duplicado e exibiam loading
  durante a tentativa com Google.
* `GoogleAuthService` ja convertia erros do plugin em `GoogleAuthException` e
  `AuthService` ja salvava sessao local no sucesso.
* A lacuna confirmada era o cancelamento silencioso: quando o provedor retornava
  `null`, as telas apenas paravam o loading e nao mostravam nenhum feedback.
* As mensagens de falha tambem nao estavam padronizadas para o roteiro do teste
  fisico 2, e o Cadastro nao diferenciava falha ao preparar conta Google.
* A persistencia da H.4 permanecia correta: somente o `usuario_id` local deve
  ser salvo apos sucesso; falha ou cancelamento nao devem criar sessao.

### Correcao realizada

* Cancelamento do Google Login agora mostra `Entrada com Google cancelada.`
  sem erro assustador e sem navegar.
* Falha geral mostra mensagem amigavel orientando verificar conexao e tentar
  novamente.
* Falha provavel de configuracao mostra mensagem segura informando que a
  configuracao do app pode precisar ser revisada, sem expor SHA, chaves,
  stacktrace ou detalhes do plugin.
* Cadastro usa mensagem especifica quando nao consegue criar/preparar a conta
  com Google.
* O botao `GoogleSignInButton` continua desabilitado durante loading e agora
  exibe `Entrando com Google...`.
* Sucesso continua passando por `AuthService`, criando/recuperando o usuario
  local e salvando a sessao local via `AuthSessionService`.
* Falha e cancelamento nao salvam sessao e nao navegam para Home.
* O token Google continua restrito a `GoogleIdentity` em memoria e nao e
  persistido como sessao.

### Testes automatizados

Testes criados ou alterados:

* `test/features/voices/services/google_auth_service_test.dart`
  * mensagem para plataforma sem suporte agora e segura/configuracao;
  * mensagens publicas nao vazam termos tecnicos.
* `test/features/voices/services/auth_service_test.dart`
  * falha ao resolver usuario local nao salva sessao;
  * sucesso com Google persiste somente `usuario_id` e startup restaura a
    sessao;
  * token Google nao e persistido.
* `test/features/voices/pages/login_page_test.dart`
  * cancelamento mostra feedback;
  * falhas mostram mensagens amigaveis;
  * falhas nao salvam sessao;
  * mensagens visiveis nao contem termos tecnicos.
* `test/features/voices/pages/cadastro_page_test.dart`
  * cancelamento mostra feedback;
  * falha de preparacao da conta Google mostra mensagem especifica de cadastro;
  * falhas nao salvam sessao;
  * mensagens visiveis nao contem termos tecnicos.
* `test/widgets/google_sign_in_button_widget_test.dart`
  * loading exibe `Entrando com Google...` e desabilita o botao.
* `test/widgets/core_ui_widget_test.dart`
  * filtros publicos removem termos como `GoogleSignInException`, SHA,
    Firebase, `client_id` e token.

### Teste manual recomendado

1. Rodar app no Android fisico.
2. Abrir Login.
3. Tocar em `Entrar com Google`.
4. Confirmar que aparece estado de carregamento.
5. Cancelar selecao de conta, se possivel.
6. Confirmar que o app nao trava e mostra feedback adequado.
7. Tentar novamente.
8. Se Google Login funcionar, confirmar que entra na Home.
9. Fechar e abrir o app.
10. Confirmar que a sessao foi restaurada.
11. Fazer logout.
12. Tentar Google Login sem internet.
13. Confirmar mensagem amigavel.
14. Confirmar que nao aparecem termos tecnicos como SHA, Firebase,
    PlatformException, stacktrace, token ou API key.

## H.6 - Correcao do scroll por voz na Home e final real da lista

### Bugs corrigidos

* Na Home, os comandos `descer`, `subir`, `ir para o topo` e `ir para o fim`
  eram reconhecidos pelo parser, mas nao executavam scroll na tela.
* Em telas com listas, `ir para o fim` podia parar antes do final visual real
  quando o tamanho rolavel mudava durante ou logo apos a animacao.

### Diagnostico tecnico

* `CommandService` ja separava corretamente comandos de scroll de comandos de
  navegacao como `tela inicial` e `voltar`.
* `VoiceScrollHandler` ja era o ponto compartilhado usado por listas como
  projetos, gravacoes, historico, dashboard e configuracoes.
* A Home usava `SingleChildScrollView`, mas nao possuia `ScrollController`
  proprio e nao registrava os tipos `scrollBaixo`, `scrollCima`, `scrollTopo`
  e `scrollFim` no `VoiceCommandDispatcher`.
* O comando `ir para o fim` calculava `maxScrollExtent` apenas antes da
  animacao. Se o layout/lista atualizasse o tamanho rolavel durante o movimento,
  a animacao parava no limite antigo.

### Correcao realizada

* A Home passou a ter `ScrollController` proprio, descartado no `dispose`.
* A Home passou a encaminhar os quatro comandos de scroll para
  `VoiceScrollHandler`.
* `VoiceScrollHandler` passou a fazer um ajuste final apos o frame seguinte ao
  rolar para o fim, usando o `maxScrollExtent` mais recente.
* Feedback de limite foi padronizado com mensagens amigaveis:
  `Nao ha mais conteudo para rolar.`, `Voce ja esta no topo.` e
  `Voce ja esta no fim da lista.`.
* `tela inicial` e `voltar` continuam seguindo o fluxo de navegacao, sem virar
  comandos de scroll.
* Nenhuma regra de autenticacao, Google Login, player, comandos personalizados,
  editor, banco ou parser global foi alterada.

### Testes automatizados

Testes criados ou alterados:

* `test/features/voices/coordination/voice_scroll_handler_test.dart`
  * controller sem clients retorna feedback amigavel;
  * `descer` aumenta offset;
  * `subir` reduz offset;
  * `ir para o topo` vai para offset zero;
  * `ir para o fim` vai para o limite final;
  * `ir para o fim` ajusta se o limite final mudar apos layout;
  * ja no topo e ja no fim retornam mensagens amigaveis.
* `test/features/home/pages/home_page_test.dart`
  * Home aceita `descer`;
  * Home aceita `subir`;
  * Home aceita `ir para o topo`;
  * Home aceita `ir para o fim` ate o final real;
  * `tela inicial` e `voltar` continuam como navegacao, sem rolar a tela.

### Teste manual recomendado

1. Rodar app no Android fisico.
2. Fazer login.
3. Na Home, dizer `descer`.
4. Confirmar que a Home rola para baixo.
5. Dizer `subir`.
6. Confirmar que a Home rola para cima.
7. Dizer `ir para o fim`.
8. Confirmar que chega ao final real da Home.
9. Dizer `ir para o topo`.
10. Confirmar que volta ao topo.
11. Dizer `tela inicial`.
12. Confirmar que continua sendo navegacao para Home.
13. Abrir Meus Projetos ou Minhas Gravacoes.
14. Dizer `ir para o fim`.
15. Confirmar que chega ao final real da lista.
16. Dizer `voltar`.
17. Confirmar que volta tela e nao rola.
