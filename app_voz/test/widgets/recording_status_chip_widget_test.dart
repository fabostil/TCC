import 'package:app_voz/features/recordings/widgets/recording_status_chip.dart';
import 'package:app_voz/models/gravacao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renderiza rotulos dos status conhecidos de gravacao', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RecordingStatusChip(status: GravacaoStatus.concluida),
              RecordingStatusChip(status: GravacaoStatus.interrompida),
              RecordingStatusChip(status: GravacaoStatus.arquivoAusente),
              RecordingStatusChip(status: GravacaoStatus.excluida),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Concluída'), findsOneWidget);
    expect(find.text('Interrompida'), findsOneWidget);
    expect(find.text('Arquivo ausente'), findsOneWidget);
    expect(find.text('Excluída'), findsOneWidget);
  });

  testWidgets('renderiza status indefinido para valor desconhecido', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RecordingStatusChip(status: 'pendente_upload')),
      ),
    );

    expect(find.text('Indefinida'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
  });
}
