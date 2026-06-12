import 'package:app_voz/features/voices/coordination/voice_command_dispatcher.dart';
import 'package:app_voz/features/voices/coordination/voice_scroll_handler.dart';
import 'package:app_voz/features/voices/services/command_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const commandService = CommandService();

  CommandResult command(String text) => commandService.interpret(text);

  Future<void> pumpScrollable(
    WidgetTester tester,
    ScrollController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: ListView.builder(
              controller: controller,
              itemCount: 40,
              itemExtent: 48,
              itemBuilder: (context, index) => Text('Item $index'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<VoiceCommandPageResult?> handleAndSettle(
    WidgetTester tester,
    VoiceScrollHandler handler,
    CommandResult result,
  ) async {
    final future = handler.handle(result);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    return await future;
  }

  test('sem ScrollController anexado retorna mensagem segura', () async {
    final controller = ScrollController();
    final result = await VoiceScrollHandler(
      controller: controller,
    ).handle(command('descer'));

    expect(result?.handled, isTrue);
    expect(result?.statusMessage, 'Nao ha lista para rolar nesta tela.');
  });

  testWidgets('scroll down aumenta o offset sem ultrapassar limites', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpScrollable(tester, controller);
    final before = controller.offset;

    final result = await handleAndSettle(
      tester,
      VoiceScrollHandler(controller: controller),
      command('descer'),
    );

    expect(result?.handled, isTrue);
    expect(controller.offset, greaterThan(before));
    expect(
      controller.offset,
      lessThanOrEqualTo(controller.position.maxScrollExtent),
    );
  });

  testWidgets('scroll up reduz o offset sem ficar negativo', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpScrollable(tester, controller);
    controller.jumpTo(500);
    await tester.pump();
    final before = controller.offset;

    final result = await handleAndSettle(
      tester,
      VoiceScrollHandler(controller: controller),
      command('subir'),
    );

    expect(result?.handled, isTrue);
    expect(controller.offset, lessThan(before));
    expect(controller.offset, greaterThanOrEqualTo(0));
  });

  testWidgets('topo rola para o inicio da lista', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpScrollable(tester, controller);
    controller.jumpTo(500);
    await tester.pump();

    final result = await handleAndSettle(
      tester,
      VoiceScrollHandler(controller: controller),
      command('ir para o topo'),
    );

    expect(result?.handled, isTrue);
    expect(controller.offset, 0);
  });

  testWidgets('fim rola para o maxScrollExtent', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpScrollable(tester, controller);

    final result = await handleAndSettle(
      tester,
      VoiceScrollHandler(controller: controller),
      command('fim da lista'),
    );

    expect(result?.handled, isTrue);
    expect(controller.offset, controller.position.maxScrollExtent);
  });
}
