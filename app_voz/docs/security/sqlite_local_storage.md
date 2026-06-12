# Armazenamento local SQLite e criptografia em repouso

## Contexto do projeto

O Assistente Musical Voice-First e um aplicativo Flutter Android desenvolvido como TCC academico para musicos independentes. O app usa armazenamento local via SQLite/sqflite para persistir dados necessarios ao fluxo de producao musical e aos comandos de voz.

Conforme o schema atual em `lib/database/app_database.dart` e nos arquivos de tabela em `lib/database/tables/`, o banco local armazena dados do app nas tabelas `usuario`, `projeto`, `gravacao`, `comando_voz`, `comando_personalizado`, `historico_acao` e `configuracao_app`.

## Estado atual

O projeto usa SQLite local via `sqflite`.

O banco local nao esta criptografado em repouso. Nao ha uso atual de SQLCipher, `sqflite_sqlcipher` ou mecanismo equivalente de criptografia completa do arquivo de banco.

A protecao de senha foi endurecida com PBKDF2-HMAC-SHA256, salt individual por usuario e migracao progressiva de hashes legados SHA-256. Esse endurecimento reduz o impacto de um vazamento do banco para credenciais locais, mas nao criptografa o restante do conteudo local.

## Risco tecnico

Se um atacante obtiver acesso ao arquivo fisico do banco no dispositivo, em backup, em ambiente comprometido ou em aparelho com root, dados nao criptografados podem ser lidos diretamente.

As senhas locais possuem protecao especifica por hash PBKDF2-HMAC-SHA256 com salt individual. Os demais dados locais, como projetos, gravacoes cadastradas, comandos, historico e configuracoes, continuam legiveis no banco se o arquivo SQLite for extraido.

## Justificativa de escopo academico

A decisao de nao implementar criptografia completa do SQLite nesta fase e aceitavel no escopo do TCC porque o foco principal do projeto e a arquitetura voice-first, o fluxo de gravacao, os comandos de voz e a persistencia local.

O projeto nao possui backend de producao com sincronizacao remota de dados sensiveis, e a aplicacao esta em contexto academico/controlado. Os principais riscos imediatos da auditoria foram mitigados primeiro: senha com PBKDF2, restricao da API key, logout centralizado e whitelist de migrations.

Essa justificativa nao elimina a necessidade de criptografia em repouso em um uso de producao.

## Mitigações já aplicadas

- PBKDF2-HMAC-SHA256 com salt individual para novos usuarios locais.
- Migracao progressiva de hashes SHA-256 legados apos login valido.
- Credencial `external_provider` para usuarios exclusivamente Google.
- Restricao da API key do Google por package name e SHA-1 de debug.
- `AuthSessionService` para logout centralizado.
- Whitelist de migrations no `AppDatabase`.
- Uso de `whereArgs` nas consultas SQL principais.
- `PRAGMA foreign_keys = ON` na configuracao do banco.

## Recomendações para produção

- Avaliar SQLCipher ou `sqflite_sqlcipher` para criptografia completa do banco.
- Criptografar seletivamente campos sensiveis se a criptografia total do banco nao for adotada.
- Proteger chaves de criptografia com Android Keystore.
- Validar `idToken` Google em backend ou Firebase Auth.
- Cadastrar SHA-1/SHA-256 de release quando o keystore de release existir.
- Revisar a politica de backup Android para evitar copia indevida de dados sensiveis, caso aplicavel.

## Critério de evolução futura

Esta limitacao so podera ser considerada resolvida quando o arquivo SQLite for criptografado em repouso ou campos sensiveis forem criptografados individualmente.

A chave de criptografia nao deve estar hardcoded. Tambem deve haver teste de migracao de banco nao criptografado para banco criptografado sem perda de dados, validacao em aparelho fisico Android e atualizacao desta documentacao com a solucao real implementada.
