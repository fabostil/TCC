import 'package:app_voz/features/voices/services/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpeechResultGate', () {
    test('resultado parcial nao executa comando', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('reproduzir', isFinal: false, onResult: delivered.add);

      expect(delivered, isEmpty);
    });

    test('resultado final completo executa uma unica vez', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('reproduzir', isFinal: false, onResult: delivered.add);
      gate.add('reproduzir gravação 2', isFinal: true, onResult: delivered.add);
      gate.add('reproduzir gravação 2', isFinal: true, onResult: delivered.add);
      // done/notListening status chega e entrega o texto pendente
      gate.finalizePending(delivered.add);

      expect(delivered, ['reproduzir gravação 2']);
    });

    test(
      'status finaliza ultimo parcial quando plataforma nao marca final',
      () {
        final delivered = <String>[];
        final gate = SpeechResultGate();

        gate.add('voltar', isFinal: false, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        expect(delivered, ['voltar']);
      },
    );

    test('parcial descartado por erro nao e executado no encerramento', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('inicio', isFinal: false, onResult: delivered.add);
      gate.clearPending();
      gate.finalizePending(delivered.add);

      expect(delivered, isEmpty);
    });

    test('comando duplicado proximo nao executa em nova sessao', () {
      var now = DateTime(2026, 6, 15, 10);
      final delivered = <String>[];
      final gate = SpeechResultGate(now: () => now);

      // Sessão 1: done entrega 'dashboard'
      gate.add('dashboard', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      // Sessão 2: 1s depois (dentro do cooldown de 2s)
      now = now.add(const Duration(seconds: 1));
      gate.add('dashboard', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      expect(delivered, ['dashboard']);
    });
  });

  // ── H11.4: testes de debounce para STT parcial ──────────────────────────────
  group('SpeechResultGate - debounce (H11.4)', () {
    // 1. isFinal nao entrega resultado imediatamente
    test('isFinal nao entrega resultado imediatamente (debounce pendente)', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('gravar', isFinal: true, onResult: delivered.add);

      // Timer de debounce ainda não disparou — nada deve ser entregue
      expect(delivered, isEmpty);
    });

    // 2. finalizePending apos isFinal entrega resultado
    test('finalizePending apos isFinal entrega resultado imediatamente', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('gravar', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      expect(delivered, ['gravar']);
    });

    // 3. segundo isFinal dentro da janela substitui o primeiro no buffer
    test('segundo isFinal substitui fragmento anterior no buffer', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('novo', isFinal: true, onResult: delivered.add);
      gate.add('novo projeto', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      expect(delivered, ['novo projeto']);
    });

    // 4. fragmento curto (isFinal precoce) nao e processado antes da frase completa
    test(
      'fragmento precoce nao e processado quando frase completa chega a seguir',
      () {
        final delivered = <String>[];
        final gate = SpeechResultGate();

        // Android emite isFinal prematuro para 'novo'
        gate.add('novo', isFinal: true, onResult: delivered.add);
        // Nada entregue ainda (debounce)
        expect(delivered, isEmpty);

        // Frase completa chega antes do timer expirar
        gate.add('novo projeto', isFinal: true, onResult: delivered.add);
        // done/notListening entrega apenas a frase completa
        gate.finalizePending(delivered.add);

        expect(delivered, ['novo projeto']);
      },
    );

    // 5. clearPending cancela timer: finalizePending posterior entrega nada
    test('clearPending cancela debounce pendente', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('gravar', isFinal: true, onResult: delivered.add);
      gate.clearPending(); // erro ou route push cancela a sessão
      gate.finalizePending(delivered.add);

      expect(delivered, isEmpty);
    });

    // 6. parcial nao inicia timer de debounce
    test('resultado parcial nao inicia timer de debounce', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('gra', isFinal: false, onResult: delivered.add);
      gate.add('grav', isFinal: false, onResult: delivered.add);

      // Nenhum timer iniciado; sem finalizePending, nada é entregue
      expect(delivered, isEmpty);
    });

    // 7. parcial seguido de finalizePending entrega o parcial (done sem isFinal)
    test('done sem isFinal entrega ultimo parcial', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('gra', isFinal: false, onResult: delivered.add);
      gate.add('gravar', isFinal: false, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      expect(delivered, ['gravar']);
    });

    // 8. isFinal vazio ignorado; finalizePending entrega nada
    test('isFinal com texto vazio e ignorado', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      expect(delivered, isEmpty);
    });

    // 9. texto com so espacos ignorado apos isFinal
    test('isFinal com apenas espacos e ignorado', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('   ', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      expect(delivered, isEmpty);
    });

    // 10. finalizePending e idempotente
    test('finalizePending e idempotente: segunda chamada nao reentrega', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('projetos', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add);
      gate.finalizePending(delivered.add); // chamada duplicada

      expect(delivered, ['projetos']);
    });

    // 11. cooldown ainda e respeitado apos debounce
    test('cooldown de duplicata e respeitado apos finalizePending', () {
      var now = DateTime(2026, 6, 19, 10);
      final delivered = <String>[];
      final gate = SpeechResultGate(now: () => now);

      gate.add('configuracoes', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      now = now.add(const Duration(milliseconds: 500));
      gate.add('configuracoes', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add); // dentro do cooldown (2s)

      expect(delivered, ['configuracoes']); // apenas uma entrega
    });

    // 12. cooldown expirado: mesmo texto e reentregue
    test('apos cooldown expirado mesmo texto e entregue novamente', () {
      var now = DateTime(2026, 6, 19, 10);
      final delivered = <String>[];
      final gate = SpeechResultGate(now: () => now);

      gate.add('gravacoes', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      now = now.add(const Duration(seconds: 3)); // cooldown expirado
      gate.add('gravacoes', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      expect(delivered, ['gravacoes', 'gravacoes']);
    });

    // 13. reset limpa cooldown
    test('reset limpa cooldown: mesmo texto entregue novamente apos reset', () {
      var now = DateTime(2026, 6, 19, 10);
      final delivered = <String>[];
      final gate = SpeechResultGate(now: () => now);

      gate.add('historico', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      now = now.add(const Duration(milliseconds: 200)); // dentro do cooldown
      gate.reset();

      gate.add('historico', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      expect(delivered, ['historico', 'historico']);
    });

    // 14. isFinal substitui parcial no buffer
    test('isFinal substitui parcial no buffer ao chegar apos parcials', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('gra', isFinal: false, onResult: delivered.add);
      gate.add('gravar ideia', isFinal: true, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      expect(delivered, ['gravar ideia']);
    });

    // 15. parcial apos isFinal atualiza buffer sem cancelar timer
    test(
      'parcial apos isFinal atualiza buffer; finalizePending entrega o parcial',
      () {
        final delivered = <String>[];
        final gate = SpeechResultGate();

        gate.add('novo', isFinal: true, onResult: delivered.add);
        // parcial chega antes do timer disparar (STT enviou mais audio)
        gate.add('novo projeto musical', isFinal: false, onResult: delivered.add);
        // done entrega o buffer atualizado
        gate.finalizePending(delivered.add);

        expect(delivered, ['novo projeto musical']);
      },
    );

    // 16. multiplos parciais seguidos de done entrega o ultimo parcial
    test('multiplos parciais seguidos: done entrega apenas o ultimo', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('g', isFinal: false, onResult: delivered.add);
      gate.add('gr', isFinal: false, onResult: delivered.add);
      gate.add('gra', isFinal: false, onResult: delivered.add);
      gate.add('gravar', isFinal: false, onResult: delivered.add);
      gate.finalizePending(delivered.add);

      expect(delivered, ['gravar']);
    });

    // 17. parcial + isFinal menor + isFinal maior + done: entrega o maior
    test('frase completa substitui fragmento isFinal precoce', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('novo', isFinal: false, onResult: delivered.add);
      gate.add('novo', isFinal: true, onResult: delivered.add); // fragmento precoce
      // ainda nao entregou nada (debounce)
      expect(delivered, isEmpty);
      gate.add('novo projeto', isFinal: true, onResult: delivered.add); // completo
      gate.finalizePending(delivered.add); // done

      expect(delivered, ['novo projeto']);
    });

    // 18. sessao sem qualquer isFinal: done entrega ultimo parcial (plataformas sem final)
    test('sessao sem isFinal: done entrega ultimo parcial registrado', () {
      final delivered = <String>[];
      final gate = SpeechResultGate();

      gate.add('meu', isFinal: false, onResult: delivered.add);
      gate.add('meu projeto', isFinal: false, onResult: delivered.add);
      gate.finalizePending(delivered.add); // plataforma encerra sem isFinal

      expect(delivered, ['meu projeto']);
    });
  });

  // ── H11.5: ordem Android dictation — gate entrega fragmento por design ────────
  //
  // No modo ListenMode.dictation com partialResults=true, o Android emite
  // isFinal=true para fragmentos prematuros ("meus") e logo done. O gate
  // entrega o fragmento imediatamente ao receber done+finalizePending.
  // A coalescência real é feita no mixin (janela 250ms), não no gate.
  // Estes testes documentam o comportamento do gate nesse cenário e garantem
  // que a camada abaixo (gate) permanece estável após as correções H11.5.
  group('SpeechResultGate - ordem Android dictation (H11.5)', () {
    // 1. done imediatamente apos isFinal entrega o fragmento (comportamento do gate)
    test(
      'done logo apos isFinal entrega o fragmento — coalescencia e responsabilidade do mixin',
      () {
        final delivered = <String>[];
        final gate = SpeechResultGate();

        // Android: isFinal="meus" → done
        gate.add('meus', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add); // simula done imediato

        // Gate entrega "meus" — mixin deve segurar e aguardar "meus projetos"
        expect(delivered, ['meus']);
      },
    );

    // 2. segundo isFinal+done substitui o primeiro se finalizePending nao foi chamado
    test(
      'segundo isFinal antes de done substitui primeiro no buffer',
      () {
        final delivered = <String>[];
        final gate = SpeechResultGate();

        gate.add('meus', isFinal: true, onResult: delivered.add);
        // done NAO chega antes do segundo isFinal: timer ainda ativo
        gate.add('meus projetos', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        expect(delivered, ['meus projetos']);
      },
    );

    // 3. "novo" substituido por "novo projeto" quando done chega apos ambos
    test(
      'novo substituido por novo projeto quando done chega apos ambos isFinal',
      () {
        final delivered = <String>[];
        final gate = SpeechResultGate();

        gate.add('novo', isFinal: true, onResult: delivered.add);
        gate.add('novo projeto', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        expect(delivered, ['novo projeto']);
      },
    );

    // 4. parcial + isFinal precoce + done + isFinal completo: gate entrega dois
    test(
      'isFinal precoce com done entre eles gera duas entregas do gate',
      () {
        final delivered = <String>[];
        final gate = SpeechResultGate();

        // Sessao 1: isFinal="novo" → done
        gate.add('novo', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        // Sessao 2: isFinal="novo projeto" → done
        gate.add('novo projeto', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        // Gate entrega os dois; o mixin com janela 250ms coalesceria para um
        expect(delivered, ['novo', 'novo projeto']);
      },
    );

    // 5. "minhas" → done, "minhas gravacoes" → done: gate entrega dois
    test(
      'minhas e minhas gravacoes entregues separadamente pelo gate',
      () {
        final delivered = <String>[];
        final gate = SpeechResultGate();

        gate.add('minhas', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        gate.add('minhas gravacoes', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        expect(delivered, ['minhas', 'minhas gravacoes']);
      },
    );

    // 6. "nome do projeto" → done, "nome do projeto abacate" → done
    test(
      'nome do projeto e nome do projeto abacate entregues separados pelo gate',
      () {
        final delivered = <String>[];
        final gate = SpeechResultGate();

        gate.add('nome do projeto', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        gate.add(
          'nome do projeto abacate',
          isFinal: true,
          onResult: delivered.add,
        );
        gate.finalizePending(delivered.add);

        expect(delivered, ['nome do projeto', 'nome do projeto abacate']);
      },
    );

    // 7. parciais antes do isFinal precoce nao sao entregues
    test(
      'parciais intermediarios nao sao entregues pelo gate',
      () {
        final delivered = <String>[];
        final gate = SpeechResultGate();

        gate.add('m', isFinal: false, onResult: delivered.add);
        gate.add('me', isFinal: false, onResult: delivered.add);
        gate.add('meu', isFinal: false, onResult: delivered.add);
        gate.add('meus', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        expect(delivered, ['meus']);
      },
    );

    // 8. cooldown nao bloqueia segundo isFinal diferente (fragmento vs completo)
    test(
      'cooldown nao bloqueia entrega de frase diferente do fragmento anterior',
      () {
        var now = DateTime(2026, 6, 19, 10);
        final delivered = <String>[];
        final gate = SpeechResultGate(now: () => now);

        gate.add('meus', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        now = now.add(const Duration(milliseconds: 100));
        gate.add('meus projetos', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        // "meus" != "meus projetos": cooldown nao bloqueia
        expect(delivered, ['meus', 'meus projetos']);
      },
    );

    // 9. clearPending apos isFinal precoce cancela fragmento
    test(
      'clearPending cancela fragmento precoce antes de done',
      () {
        final delivered = <String>[];
        final gate = SpeechResultGate();

        gate.add('ir para', isFinal: true, onResult: delivered.add);
        gate.clearPending(); // erro de rede ou route push cancela a sessao
        gate.finalizePending(delivered.add);

        expect(delivered, isEmpty);
      },
    );

    // 10. sequencia completa Android dictation: tres fragmentos + frase final
    test(
      'sequencia Android dictation: gate entrega cada isFinal+done separadamente',
      () {
        final delivered = <String>[];
        final gate = SpeechResultGate();

        // Android emite multiplos isFinal antes da frase completa
        gate.add('ir', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        gate.add('ir para', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        gate.add('ir para projetos', isFinal: true, onResult: delivered.add);
        gate.finalizePending(delivered.add);

        // Gate entrega cada fragmento; mixin com 250ms coalesceria para o ultimo
        expect(delivered, ['ir', 'ir para', 'ir para projetos']);
      },
    );
  });
}
