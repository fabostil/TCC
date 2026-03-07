# App Voz — Assistente para Músicos (TCC)

Aplicativo Flutter para Android que usa voz para ajudar músicos em sessões de gravação.

## Estado atual (MVP)

O projeto já inicia com:

- reconhecimento de comandos de voz em português (`speech_to_text`);
- feedback por voz (`flutter_tts`);
- controle de sessão de gravação em nível de protótipo (iniciar/pausar/encerrar);
- criação de marcadores da sessão.

> **Importante:** neste estágio o app controla o fluxo de sessão, mas ainda não grava arquivo de áudio real. Isso entra na próxima etapa.

## Como rodar no Android

### 1) Pré-requisitos

- Flutter SDK instalado;
- Android Studio + emulador, ou celular Android com depuração USB habilitada;
- VSCode com extensões Flutter/Dart.

### 2) Instalar dependências

```bash
flutter pub get
```

### 3) Executar

```bash
flutter run
```

No primeiro uso, aceite a permissão de microfone.

## Comandos de voz já suportados

- **iniciar gravação** / **começar gravação**
- **pausar gravação** / **pausar**
- **encerrar gravação** / **parar gravação**
- **adicionar marcador** / **novo marcador**

## Como evoluir para cumprir os requisitos do TCC

### Fase 1 — Estrutura e comando de voz (concluída)
- RF01 (reconhecimento de voz)
- RF04 (marcadores)
- RF07 (resposta de voz)

### Fase 2 — Gravação real de áudio
Sugestão de pacote: `record`.

Entregas:
- iniciar/pausar/encerrar gravação real (RF02);
- salvar arquivo no dispositivo (RF03, RF05);
- garantir estabilidade durante gravação (RNF04).

### Fase 3 — Organização de sessões
Sugestões:
- usar `path_provider` para criar pasta por sessão;
- salvar metadados (nome, data, duração, marcadores) com `sqflite` ou `isar`.

Entregas:
- listagem e organização de sessões;
- busca por nome/data;
- histórico de gravações.

### Fase 4 — Reprodução e UX final
Sugestão de pacote: `just_audio`.

Entregas:
- reprodução de gravações (RF06);
- interface simples e intuitiva (RNF02);
- melhoria de responsividade e mensagens de erro (RNF01).

## Arquitetura sugerida (próximos passos)

```
lib/
  core/
    constants/
    utils/
  features/
    voice/
      pages/
      services/
      models/
    recording/
      pages/
      services/
      repositories/
```

## Checklist técnico recomendado

1. Configurar lint e formatação automática no VSCode.
2. Criar testes de unidade para parser de comandos.
3. Criar testes de widget para estados da tela.
4. Criar backlog com histórias baseadas nos RFs e RNFs.
5. Definir critérios de aceite por funcionalidade.

## Comandos úteis

```bash
flutter analyze
flutter test
flutter run
```
