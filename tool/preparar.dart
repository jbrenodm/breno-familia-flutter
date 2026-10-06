// Gera as pastas android/ e windows/ (se ainda não existirem) e aplica os ajustes do app.
// Uso: dart run tool/preparar.dart
// Pode rodar quantas vezes quiser: não sobrescreve o código em lib/ nem os testes.
import 'dart:io';

Future<void> main() async {
  if (!Directory('android').existsSync() || !Directory('windows').existsSync()) {
    stdout.writeln('Gerando plataformas Android e Windows…');
    final r = await Process.run(
      'flutter',
      ['create', '--platforms=android,windows', '--org', 'br.dev.breno', '--project-name', 'breno_financeiro', '.'],
      runInShell: true,
    );
    stdout.write(r.stdout);
    stderr.write(r.stderr);
    if (r.exitCode != 0) exit(r.exitCode);
  }

  // Android: permissão de internet também no build de release, e nome do app.
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (manifest.existsSync()) {
    var s = manifest.readAsStringSync();
    if (!s.contains('android.permission.INTERNET')) {
      final m = RegExp(r'<manifest[^>]*>').firstMatch(s)!;
      s = s.replaceRange(m.end, m.end, '\n    <uses-permission android:name="android.permission.INTERNET"/>');
    }
    s = s.replaceAll('android:label="breno_financeiro"', 'android:label="Controle Financeiro"');
    manifest.writeAsStringSync(s);
    stdout.writeln('✓ AndroidManifest.xml');
  }

  // Windows: título da janela.
  final mainCpp = File('windows/runner/main.cpp');
  if (mainCpp.existsSync()) {
    final s = mainCpp.readAsStringSync().replaceAll('L"breno_financeiro"', 'L"Controle Financeiro"');
    mainCpp.writeAsStringSync(s);
    stdout.writeln('✓ windows/runner/main.cpp');
  }

  // flutter create pode criar test/widget_test.dart apontando para um MyApp que não existe.
  final wt = File('test/widget_test.dart');
  if (wt.existsSync() && wt.readAsStringSync().contains('MyApp')) {
    wt.deleteSync();
    stdout.writeln('✓ removido test/widget_test.dart gerado pelo flutter create');
  }
  stdout.writeln('Pronto.');
}
