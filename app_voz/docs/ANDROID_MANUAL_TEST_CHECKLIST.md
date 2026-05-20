# Checklist Manual Android

Documento operacional para validar o app em aparelho Android real antes da entrega do TCC.

## Status Da Sessao

Preencher ao executar:

| Campo | Valor |
|-------|-------|
| Data | |
| Responsavel | |
| Aparelho | |
| Android | |
| Build | debug / release |
| Instalacao | limpa / atualizacao |
| Gemini | com chave / sem chave |
| Google Sign-In | configurado / nao configurado |
| Permissao de microfone | concedida / negada / bloqueada |
| Resultado final | aprovado / aprovado com ressalvas / reprovado |

## Preparacao

Antes do teste:

- Confirmar que `flutter analyze` esta sem issues.
- Confirmar que `flutter test` esta passando.
- Gerar APK ou rodar direto no aparelho.
- Usar instalacao limpa quando houver mudanca de banco, permissao, `applicationId`, OAuth ou `google-services.json`.
- Executar um ciclo com `GEMINI_API_KEY` e outro sem chave.

Comandos recomendados:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter devices
flutter run -d <DEVICE_ID>
```

Com Gemini:

```powershell
flutter run -d <DEVICE_ID> --dart-define=GEMINI_API_KEY=SUA_CHAVE
```

Se precisar capturar logs:

```powershell
adb logcat -c
adb logcat | findstr /i "flutter google speech record microphone firebase"
```

## Criterios Gerais De Aprovacao

- Nenhuma tela deve travar se o microfone for negado.
- Toda acao por voz deve ter fallback manual.
- A escuta continua deve parar ao navegar e voltar apenas quando a tela visivel permitir.
- O Editor deve pausar STT durante gravacao real.
- Exclusoes devem exigir confirmacao manual ou por voz.
- Login Google deve criar ou vincular usuario local sem duplicar dados.
- Logout deve voltar ao login e encerrar a sessao Google quando possivel.
- O app deve continuar utilizavel sem Gemini.

## 1. Instalacao E Entrada

| ID | Passo | Resultado esperado | Status | Evidencia/observacao |
|----|-------|--------------------|--------|----------------------|
| A01 | Instalar app limpo | App abre sem erro e mostra login | | |
| A02 | Criar usuario local com e-mail invalido | Formulario rejeita e-mail sem estrutura real | | |
| A03 | Criar usuario local com senha fraca | Formulario exige senha mais forte | | |
| A04 | Criar usuario local valido | Cadastro salva e volta para login | | |
| A05 | Fazer login local | Home abre com dados do usuario | | |
| A06 | Sair pelo botao | Volta para login sem crash | | |
| A07 | Sair por voz | Confirma logout e volta para login | | |

## 2. Google Sign-In

Pre-condicoes:

- `android/app/google-services.json` deve conter `client_type: 1` e `client_type: 3`.
- Firebase Authentication > Google deve estar ativo.
- SHA-1/SHA-256 do build instalado devem estar cadastrados.

| ID | Passo | Resultado esperado | Status | Evidencia/observacao |
|----|-------|--------------------|--------|----------------------|
| G01 | Entrar com Google em instalacao limpa | Seletor de conta abre e autentica | | |
| G02 | Concluir login Google | Home abre com nome da conta Google | | |
| G03 | Sair da Home | Sessao local encerra e volta ao login | | |
| G04 | Entrar novamente com Google | Usuario existente e reutilizado, sem duplicar conta local | | |
| G05 | Criar usuario local com mesmo e-mail Google e depois entrar com Google | Conta local e vinculada ao Google sem perder login por senha | | |

Nao aprovar se:

- aparecer erro de OAuth/configuracao;
- `idToken` nao for retornado;
- conta for duplicada para o mesmo Google/e-mail;
- logout impedir retorno ao login.

## 3. Permissao De Microfone

| ID | Cenario | Resultado esperado | Status | Evidencia/observacao |
|----|---------|--------------------|--------|----------------------|
| M01 | Primeira execucao com permissao concedida | Home ativa comandos de voz e inicia escuta | | |
| M02 | Primeira execucao com permissao negada | App permanece em modo manual e mostra orientacao | | |
| M03 | Permissao negada permanentemente | Home/Configuracoes oferecem caminho para permissoes do Android | | |
| M04 | Reativar em Configuracoes | App solicita permissao antes de persistir voz ativa | | |
| M05 | Permissao removida nas configuracoes do Android | App nao trava e orienta reativacao | | |

## 4. Navegacao Por Voz

Testar na Home:

```text
abrir projetos
abrir gravacoes
abrir dashboard
abrir historico
abrir configuracoes
abrir assistente
voltar
```

| ID | Resultado esperado | Status | Evidencia/observacao |
|----|--------------------|--------|----------------------|
| N01 | Cada comando abre a tela correta | | |
| N02 | `abrir assistente` informa que o assistente ja esta ativo | | |
| N03 | Resultado parcial duplicado nao abre a mesma tela duas vezes | | |
| N04 | Ao voltar, a Home retoma escuta continua quando configurada | | |
| N05 | Comandos globais funcionam nas telas contextuais | | |

## 5. Projetos

| ID | Comando/acao | Resultado esperado | Status | Evidencia/observacao |
|----|--------------|--------------------|--------|----------------------|
| P01 | `novo projeto` | Formulario inline aparece | | |
| P02 | `nome do projeto teste` | Campo nome e preenchido | | |
| P03 | `descricao do projeto ideia inicial` | Campo descricao e preenchido | | |
| P04 | `criar projeto` | Projeto salvo e listado | | |
| P05 | `abrir projeto teste` | Detalhes do projeto abre | | |
| P06 | `renomear projeto teste para demo` | Nome muda sem conflito | | |
| P07 | Criar projeto manualmente | Fallback manual funciona | | |

## 6. Gravacao E Editor

| ID | Passo | Resultado esperado | Status | Evidencia/observacao |
|----|-------|--------------------|--------|----------------------|
| E01 | Abrir editor de um projeto | Editor carrega e pode ouvir comandos fora da gravacao | | |
| E02 | `iniciar gravacao` | STT pausa, gravacao real inicia e controles manuais ficam ativos | | |
| E03 | Pausar manualmente | Gravacao pausa sem crash | | |
| E04 | Retomar manualmente | Gravacao continua | | |
| E05 | Parar manualmente | Arquivo e salvo e listado | | |
| E06 | Aguardar silencio configurado | Parada automatica encerra gravacao quando aplicavel | | |
| E07 | Sair do Editor durante gravacao | App pede confirmacao e salva antes de sair | | |
| E08 | Apos salvar | Escuta continua tenta voltar se configurada | | |

Nao aprovar se:

- STT e `record` tentarem usar o microfone ao mesmo tempo;
- arquivo salvo nao aparecer na lista;
- app travar ao pausar/retomar/parar;
- gravacao vazia for criada sem indicacao clara.

## 7. Gravacoes

| ID | Comando/acao | Resultado esperado | Status | Evidencia/observacao |
|----|--------------|--------------------|--------|----------------------|
| R01 | `reproduzir gravacao <nome>` | Audio toca | | |
| R02 | `parar audio` | Audio para | | |
| R03 | `abrir detalhes da gravacao <nome>` | Tela de detalhes abre | | |
| R04 | `renomear gravacao <nome> para <novo>` | Nome muda | | |
| R05 | `excluir gravacao <nome>` | Confirmacao inline aparece | | |
| R06 | `confirmar exclusao` | Registro e arquivo fisico sao removidos quando existir | | |
| R07 | `cancelar exclusao` | Nada e removido | | |

## 8. Configuracoes

| ID | Opcao | Resultado esperado | Status | Evidencia/observacao |
|----|-------|--------------------|--------|----------------------|
| C01 | Controle por voz | Valida microfone antes de ativar | | |
| C02 | Escuta continua | Liga/desliga retomada automatica | | |
| C03 | Feedback sonoro | Ativa click/haptic quando suportado | | |
| C04 | Tema escuro/claro | Persiste apos navegar ou reiniciar | | |
| C05 | Comandos personalizados | Frase salva, ativa/desativa e exclui | | |
| C06 | Tempo de silencio | Slider persiste valor | | |
| C07 | Comando global `ativar tema escuro` | Tema muda por voz | | |

## 9. Dashboard E Historico

| ID | Passo | Resultado esperado | Status | Evidencia/observacao |
|----|-------|--------------------|--------|----------------------|
| D01 | Abrir dashboard apos criar projeto/gravacao | Metricas refletem dados reais | | |
| D02 | Abrir historico | Acoes recentes aparecem | | |
| D03 | Filtrar historico | Lista muda sem quebrar estado vazio | | |
| D04 | Usar `voltar` por voz | Navegacao retorna corretamente | | |
| D05 | Usar `abrir dashboard` no historico | Dashboard abre | | |

## 10. Gemini

Com `GEMINI_API_KEY`:

| ID | Passo | Resultado esperado | Status | Evidencia/observacao |
|----|-------|--------------------|--------|----------------------|
| IA01 | Falar frase natural nao coberta pelo parser local | UI mostra IA pensando | | |
| IA02 | IA retorna intent conhecida | Acao interna executa sem texto livre inseguro | | |
| IA03 | Timeout/rede ruim | App nao trava e escuta se recupera | | |

Sem `GEMINI_API_KEY`:

| ID | Passo | Resultado esperado | Status | Evidencia/observacao |
|----|-------|--------------------|--------|----------------------|
| IA04 | Usar comandos locais | Funcionam normalmente | | |
| IA05 | Usar comando desconhecido | App informa que NLU nao esta configurado | | |

## 11. Regressao De Escuta

Executar o ciclo:

```text
Home -> Projetos -> Detalhes -> Editor -> voltar -> Gravacoes -> Detalhes -> voltar -> Home
```

| ID | Resultado esperado | Status | Evidencia/observacao |
|----|--------------------|--------|----------------------|
| V01 | So a tela visivel usa o microfone | | |
| V02 | Nao ha duas escutas simultaneas | | |
| V03 | Ao navegar, a escuta anterior para | | |
| V04 | Ao voltar, a escuta retoma quando configurada | | |
| V05 | Durante gravacao, escuta por voz fica pausada | | |

## Falhas Encontradas

| ID | Tela/fluxo | Severidade | Descricao | Reproducao | Status |
|----|------------|------------|-----------|------------|--------|
| | | critica / alta / media / baixa | | | aberta / corrigida / aceita |

## Decisao Final

Marcar apenas depois de executar os cenarios principais:

- [ ] Login local aprovado.
- [ ] Google Sign-In aprovado.
- [ ] Permissoes aprovadas.
- [ ] Navegacao por voz aprovada.
- [ ] Gravacao real aprovada.
- [ ] Reproducao/renomeacao/exclusao aprovadas.
- [ ] Configuracoes persistentes aprovadas.
- [ ] Dashboard/historico aprovados.
- [ ] Gemini aprovado ou limitação documentada.

Resultado:

```text
Aprovado para apresentacao: sim / nao
Ressalvas:
```
