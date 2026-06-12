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
