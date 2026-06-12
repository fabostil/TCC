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
