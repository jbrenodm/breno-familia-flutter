import 'package:breno_financeiro/data/remoto.dart';

/// Servidor falso em memória, com o mesmo comportamento que importa do Supabase:
/// upsert por chave, updated_at definido pelo servidor e consulta "alterados desde".
class RemotoFalso implements Remoto {
  final Map<String, Map<String, Map<String, dynamic>>> tabelas = {'grupos': {}, 'itens': {}, 'valores': {}};
  final Map<String, Map<String, dynamic>> lares = {};
  final Map<String, String> membros = {}; // userId → larId
  String usuario = 'u1';
  bool offline = false;
  int chamadasUpsert = 0;
  DateTime _relogio = DateTime.utc(2026, 1, 1);
  void Function()? _ouvinte;

  String _agora() => (_relogio = _relogio.add(const Duration(seconds: 1))).toIso8601String();
  void _rede() {
    if (offline) throw Exception('SocketException: Failed host lookup');
  }

  String _chave(String t, Map<String, dynamic> r) => t == 'valores' ? '${r['item_id']}:${r['mes']}' : r['id'] as String;

  @override
  Future<void> upsert(String tabela, List<Map<String, dynamic>> linhas, {required String onConflict}) async {
    _rede();
    chamadasUpsert++;
    for (final r in linhas) {
      tabelas[tabela]![_chave(tabela, r)] = {...r, 'updated_at': _agora()};
    }
  }

  @override
  Future<void> atualizarLar(String larId, Map<String, dynamic> campos) async {
    _rede();
    lares[larId]!.addAll({...campos, 'updated_at': _agora()});
  }

  @override
  Future<List<Map<String, dynamic>>> mudancas(String tabela, String larId, String? desde) async {
    _rede();
    final d = desde == null ? null : DateTime.parse(desde);
    return [
      for (final r in tabelas[tabela]!.values)
        if (r['lar_id'] == larId && (d == null || DateTime.parse(r['updated_at'] as String).isAfter(d))) Map.of(r),
    ];
  }

  @override
  Future<Map<String, dynamic>?> lar(String larId) async {
    _rede();
    return lares[larId];
  }

  @override
  Future<String?> meuLar() async {
    _rede();
    return membros[usuario];
  }

  @override
  Future<String> criarLar(String nome) async {
    _rede();
    final id = 'lar-${lares.length + 1}';
    lares[id] = {'id': id, 'nome': nome, 'meta_pct': 30, 'codigo': 'ABC12345', 'updated_at': _agora()};
    membros[usuario] = id;
    return id;
  }

  @override
  Future<String> entrarNoLar(String codigo) async {
    _rede();
    final lar = lares.values.where((l) => l['codigo'] == codigo.toUpperCase()).firstOrNull;
    if (lar == null) throw Exception('Código de convite inválido');
    membros[usuario] = lar['id'] as String;
    return lar['id'] as String;
  }

  @override
  void ouvir(String larId, void Function() aoMudar) => _ouvinte = aoMudar;

  @override
  void pararDeOuvir() => _ouvinte = null;

  void avisarMudanca() => _ouvinte?.call();
}
