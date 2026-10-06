import 'package:breno_familia_flutter/ui/comum.dart';
import 'package:breno_familia_flutter/ui/tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('campo de valor aceita contas e grava ao sair do campo', (tester) async {
    double? gravado;
    await tester.pumpWidget(MaterialApp(
      theme: criarTema(Brightness.light),
      home: Scaffold(
        body: Column(children: [
          CampoValor(valor: 0, aoMudar: (v) => gravado = v),
          const TextField(key: Key('outro')),
        ]),
      ),
    ));
    await tester.tap(find.byType(CampoValor));
    await tester.pump();
    await tester.enterText(find.byType(CampoValor), '120+35,90');
    await tester.tap(find.byKey(const Key('outro')));
    await tester.pumpAndSettle();
    expect(gravado, 155.9);
  });
}
