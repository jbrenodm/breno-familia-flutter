import 'package:supabase_flutter/supabase_flutter.dart';

/// Acesso ao servidor. O [Repositorio] só conhece esta interface, o que permite testá-lo com uma versão falsa.
abstract class Remoto {
  /// Grava (insere ou atualiza) linhas numa tabela.
  Future<void> upsert(String tabela, List<Map<String, dynamic>> linhas, {required String onConflict});

  /// Atualiza campos do lar (ex.: meta_pct).
  Future<void> atualizarLar(String larId, Map<String, dynamic> campos);

  /// Linhas da tabela alteradas depois de [desde] (ISO 8601), ou todas se null.
  Future<List<Map<String, dynamic>>> mudancas(String tabela, String larId, String? desde);

  Future<Map<String, dynamic>?> lar(String larId);
  Future<String?> meuLar();
  Future<String> criarLar(String nome);
  Future<String> entrarNoLar(String codigo);

  /// Avisa quando outra pessoa altera algo no lar (tempo real).
  void ouvir(String larId, void Function() aoMudar);
  void pararDeOuvir();
}

class RemotoSupabase implements Remoto {
  RemotoSupabase(this.client);
  final SupabaseClient client;
  RealtimeChannel? _canal;

  static const _pagina = 1000; // limite padrão de linhas por requisição no Supabase
  static const _chaves = {
    'grupos': ['id'],
    'itens': ['id'],
    'valores': ['item_id', 'mes'],
  };

  @override
  Future<void> upsert(String tabela, List<Map<String, dynamic>> linhas, {required String onConflict}) async {
    for (var i = 0; i < linhas.length; i += 500) {
      final lote = linhas.sublist(i, i + 500 > linhas.length ? linhas.length : i + 500);
      await client.from(tabela).upsert(lote, onConflict: onConflict);
    }
  }

  @override
  Future<void> atualizarLar(String larId, Map<String, dynamic> campos) async {
    await client.from('lares').update(campos).eq('id', larId);
  }

  @override
  Future<List<Map<String, dynamic>>> mudancas(String tabela, String larId, String? desde) async {
    final todas = <Map<String, dynamic>>[];
    var de = 0;
    while (true) {
      var q = client.from(tabela).select().eq('lar_id', larId);
      if (desde != null) q = q.gt('updated_at', desde);
      var o = q.order('updated_at', ascending: true);
      for (final c in _chaves[tabela] ?? const ['id']) {
        o = o.order(c, ascending: true);
      }
      final res = await o.range(de, de + _pagina - 1);
      todas.addAll(res);
      if (res.length < _pagina) break;
      de += _pagina;
    }
    return todas;
  }

  @override
  Future<Map<String, dynamic>?> lar(String larId) async =>
      await client.from('lares').select('id, nome, meta_pct, codigo, updated_at').eq('id', larId).maybeSingle();

  @override
  Future<String?> meuLar() async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return null;
    final res = await client.from('membros').select('lar_id').eq('user_id', uid).order('criado_em').limit(1);
    return res.isEmpty ? null : res.first['lar_id'] as String;
  }

  @override
  Future<String> criarLar(String nome) async => (await client.rpc('criar_lar', params: {'p_nome': nome})) as String;

  @override
  Future<String> entrarNoLar(String codigo) async =>
      (await client.rpc('entrar_no_lar', params: {'p_codigo': codigo})) as String;

  @override
  void ouvir(String larId, void Function() aoMudar) {
    pararDeOuvir();
    var canal = client.channel('lar-$larId');
    for (final t in const ['lares', 'grupos', 'itens', 'valores']) {
      canal = canal.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: t,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: t == 'lares' ? 'id' : 'lar_id',
          value: larId,
        ),
        callback: (_) => aoMudar(),
      );
    }
    _canal = canal.subscribe();
  }

  @override
  void pararDeOuvir() {
    final c = _canal;
    _canal = null;
    if (c != null) client.removeChannel(c);
  }
}
