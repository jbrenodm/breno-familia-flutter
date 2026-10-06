import 'dart:convert';
import 'dart:io';

/// Guarda o estado do app no aparelho (dados + fila de envio + cursores).
abstract class Armazenamento {
  Future<Map<String, dynamic>?> ler();
  Future<void> gravar(Map<String, dynamic> estado);
}

/// Arquivo JSON na pasta de dados do app. Grava num temporário e renomeia, para nunca deixar o arquivo pela metade.
class ArmazenamentoArquivo implements Armazenamento {
  ArmazenamentoArquivo(this.caminho);
  final String caminho;

  @override
  Future<Map<String, dynamic>?> ler() async {
    final f = File(caminho);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> gravar(Map<String, dynamic> estado) async {
    final tmp = File('$caminho.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(jsonEncode(estado), flush: true);
    await tmp.rename(caminho);
  }
}

/// Para testes.
class ArmazenamentoMemoria implements Armazenamento {
  Map<String, dynamic>? estado;

  @override
  Future<Map<String, dynamic>?> ler() async => estado == null ? null : jsonDecode(jsonEncode(estado)) as Map<String, dynamic>;

  @override
  Future<void> gravar(Map<String, dynamic> e) async => estado = jsonDecode(jsonEncode(e)) as Map<String, dynamic>;
}
