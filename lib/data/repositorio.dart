import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'armazenamento.dart';
import 'modelo.dart';
import 'remoto.dart';

enum EstadoSync { sincronizado, sincronizando, offline, erro }

/// Uma alteração local que ainda precisa chegar ao servidor.
class Operacao {
  Operacao(this.tabela, this.linha, this.seq);
  final String tabela; // grupos | itens | valores | lares
  final Map<String, dynamic> linha;
  final int seq;

  Map<String, dynamic> toJson() => {'t': tabela, 'l': linha, 's': seq};
  factory Operacao.fromJson(Map<String, dynamic> j) =>
      Operacao(j['t'] as String, Map<String, dynamic>.from(j['l'] as Map), (j['s'] as num).toInt());
}

/// Fonte única de dados do app.
///
/// Offline-first: toda alteração vale na hora no aparelho, entra numa fila (salva em disco) e é enviada
/// sozinha assim que houver conexão. Não existe "Publicar": o usuário só vê se está sincronizado ou offline.
///
/// Garantias:
/// 1. Valor de item é gravado por célula (item, mês): duas pessoas lançando ao mesmo tempo não se sobrescrevem.
/// 2. Estrutura (grupos/itens) é gravada por linha, com IDs estáveis. Nada é apagado: exclusão = `excluido`.
/// 3. Ao receber do servidor, linhas com alteração local ainda na fila são ignoradas (a local vence até ser enviada).
/// 4. Envio e recebimento rodam um de cada vez ([sincronizar] é serializado).
class Repositorio extends ChangeNotifier {
  Repositorio({
    required this.remoto,
    required this.armazenamento,
    this.atrasoEnvio = const Duration(milliseconds: 800),
    String Function()? novoId,
  }) : _novoId = novoId ?? (() => const Uuid().v4());

  final Remoto remoto;
  final Armazenamento armazenamento;
  final Duration atrasoEnvio;
  final String Function() _novoId;

  String? larId;
  String? larNome;
  String? larCodigo;
  Dados dados = Dados();
  final Map<String, Operacao> _fila = {};
  final Map<String, String> _cursores = {};
  int _seq = 0;

  EstadoSync estado = EstadoSync.sincronizado;
  String? mensagem;
  DateTime? ultimaSync;

  int get pendentes => _fila.length;
  bool get temLar => larId != null;

  Timer? _timer;
  Future<void>? _emAndamento;
  bool _repetir = false;
  Future<void> _gravacao = Future.value();
  bool _descartado = false;

  /* ---------------- ciclo de vida ---------------- */

  Future<void> carregar() async {
    final j = await armazenamento.ler();
    if (j == null) return;
    larId = j['larId'] as String?;
    larNome = j['larNome'] as String?;
    larCodigo = j['larCodigo'] as String?;
    if (j['dados'] is Map) dados = Dados.fromJson(Map<String, dynamic>.from(j['dados'] as Map));
    _fila
      ..clear()
      ..addAll(((j['fila'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, Operacao.fromJson(Map<String, dynamic>.from(v as Map)))));
    _cursores
      ..clear()
      ..addAll(((j['cursores'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, v as String)));
    _seq = (j['seq'] as num?)?.toInt() ?? 0;
    final u = j['ultimaSync'] as String?;
    ultimaSync = u == null ? null : DateTime.tryParse(u);
    notifyListeners();
  }

  Map<String, dynamic> _estadoJson() => {
        'larId': larId,
        'larNome': larNome,
        'larCodigo': larCodigo,
        'dados': dados.toJson(),
        'fila': {for (final e in _fila.entries) e.key: e.value.toJson()},
        'cursores': Map<String, String>.of(_cursores),
        'seq': _seq,
        'ultimaSync': ultimaSync?.toIso8601String(),
      };

  /// Grava em disco (em ordem, sem sobreposição).
  Future<void> salvar() {
    final snap = _estadoJson();
    _gravacao = _gravacao.then((_) => armazenamento.gravar(snap)).catchError((Object e) {
      debugPrint('Falha ao gravar no aparelho: $e');
    });
    return _gravacao;
  }

  /// Procura o lar do usuário no servidor. Retorna true se encontrou.
  Future<bool> localizarLar() async {
    if (larId != null) return true;
    final id = await remoto.meuLar();
    if (id == null) return false;
    await _definirLar(id);
    return true;
  }

  Future<void> criarLar(String nome, {bool comEstruturaPadrao = true}) async {
    final id = await remoto.criarLar(nome);
    await _definirLar(id);
    if (comEstruturaPadrao && dados.anos.isEmpty) criarAno(DateTime.now().year);
    await sincronizar();
  }

  Future<void> entrarNoLar(String codigo) async {
    final id = await remoto.entrarNoLar(codigo);
    await _definirLar(id);
    await sincronizar();
  }

  Future<void> _definirLar(String id) async {
    if (larId != id) {
      dados = Dados();
      _fila.clear();
      _cursores.clear();
    }
    larId = id;
    await salvar();
    notifyListeners();
  }

  /// Começa a escutar mudanças de outras pessoas e sincroniza.
  void iniciar() {
    final id = larId;
    if (id == null) return;
    try {
      remoto.ouvir(id, () => agendar(const Duration(milliseconds: 400)));
    } catch (e) {
      debugPrint('Tempo real indisponível: $e');
    }
    sincronizar();
  }

  void parar() {
    _timer?.cancel();
    try {
      remoto.pararDeOuvir();
    } catch (_) {}
  }

  @override
  void dispose() {
    _descartado = true;
    parar();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_descartado) super.notifyListeners();
  }

  /* ---------------- sincronização ---------------- */

  void agendar([Duration? atraso]) {
    _timer?.cancel();
    _timer = Timer(atraso ?? atrasoEnvio, sincronizar);
  }

  /// Envia a fila e busca novidades. Chamadas simultâneas são agrupadas.
  Future<void> sincronizar() {
    if (larId == null) return Future.value();
    final atual = _emAndamento;
    if (atual != null) {
      _repetir = true;
      return atual;
    }
    final f = _rodar();
    _emAndamento = f;
    return f;
  }

  Future<void> _rodar() async {
    try {
      do {
        _repetir = false;
        await _umaVez();
      } while (_repetir && !_descartado);
    } finally {
      _emAndamento = null;
    }
  }

  Future<void> _umaVez() async {
    estado = EstadoSync.sincronizando;
    notifyListeners();
    try {
      await _enviar();
      await _receber();
      estado = EstadoSync.sincronizado;
      mensagem = null;
      ultimaSync = DateTime.now();
    } catch (e) {
      final offline = pareceOffline(e);
      estado = offline ? EstadoSync.offline : EstadoSync.erro;
      mensagem = offline ? null : mensagemDeErro(e);
      debugPrint('Sincronização: $e');
      // Tenta de novo sozinho mais tarde (a fila continua salva no aparelho).
      if (!_descartado) agendar(const Duration(seconds: 30));
    }
    await salvar();
    notifyListeners();
  }

  Future<void> _enviar() async {
    if (_fila.isEmpty) return;
    final lar = larId!;
    final snap = Map<String, Operacao>.of(_fila);
    List<Map<String, dynamic>> linhas(String t) =>
        [for (final o in snap.values.where((o) => o.tabela == t)) {...o.linha, 'lar_id': lar}];
    final grupos = linhas('grupos'), itens = linhas('itens'), valores = linhas('valores');
    // Ordem importa: itens dependem de grupos, valores dependem de itens.
    if (grupos.isNotEmpty) await remoto.upsert('grupos', grupos, onConflict: 'id');
    if (itens.isNotEmpty) await remoto.upsert('itens', itens, onConflict: 'id');
    if (valores.isNotEmpty) await remoto.upsert('valores', valores, onConflict: 'item_id,mes');
    final larOp = snap['lar'];
    if (larOp != null) await remoto.atualizarLar(lar, larOp.linha);
    // Remove só o que não mudou durante o envio.
    snap.forEach((k, o) {
      if (_fila[k]?.seq == o.seq) _fila.remove(k);
    });
  }

  /// Margem para não perder linhas gravadas por transações que terminaram fora de ordem.
  static const _margem = Duration(minutes: 2);

  Future<void> _receber() async {
    final lar = larId!;
    final info = await remoto.lar(lar);
    if (info != null) {
      larNome = info['nome'] as String?;
      larCodigo = info['codigo'] as String?;
      if (!_fila.containsKey('lar')) dados.metaPct = (info['meta_pct'] as num?)?.toDouble() ?? dados.metaPct;
    }
    for (final t in const ['grupos', 'itens', 'valores']) {
      final c = _cursores[t];
      final desde = c == null ? null : DateTime.parse(c).subtract(_margem).toUtc().toIso8601String();
      final linhas = await remoto.mudancas(t, lar, desde);
      DateTime? maior = c == null ? null : DateTime.parse(c);
      for (final r in linhas) {
        _aplicar(t, r);
        final u = DateTime.tryParse('${r['updated_at']}');
        if (u != null && (maior == null || u.isAfter(maior))) maior = u;
      }
      if (maior != null) _cursores[t] = maior.toUtc().toIso8601String();
    }
  }

  void _aplicar(String t, Map<String, dynamic> r) {
    switch (t) {
      case 'grupos':
        final g = Grupo.fromRow(r);
        if (!_fila.containsKey('g:${g.id}')) dados.grupos[g.id] = g;
      case 'itens':
        final i = Item.fromRow(r);
        if (!_fila.containsKey('i:${i.id}')) dados.itens[i.id] = i;
      case 'valores':
        final id = r['item_id'] as String, m = (r['mes'] as num).toInt();
        if (_fila.containsKey('v:$id:$m')) return;
        final v = List<double>.of(dados.valoresDo(id));
        v[m] = (r['valor'] as num?)?.toDouble() ?? 0;
        dados.valores[id] = v;
    }
  }

  void _enfileirar(String chave, String tabela, Map<String, dynamic> linha) {
    _fila[chave] = Operacao(tabela, linha, ++_seq);
  }

  void _mudou() {
    salvar();
    notifyListeners();
    agendar();
  }

  /* ---------------- valores ---------------- */

  void definirValor(String itemId, int mes, double valor) {
    final v = round2(valor);
    if (dados.valor(itemId, mes) == v) return;
    final lista = List<double>.of(dados.valoresDo(itemId));
    lista[mes] = v;
    dados.valores[itemId] = lista;
    _enfileirar('v:$itemId:$mes', 'valores', {'item_id': itemId, 'mes': mes, 'valor': v});
    _mudou();
  }

  bool estaPendente(String itemId, int mes) => _fila.containsKey('v:$itemId:$mes');

  /// Copia do mês anterior para os itens zerados. Casa itens pelo nome do grupo + nome do item
  /// (de um ano para o outro os IDs mudam). Retorna quantos valores foram copiados.
  int copiarMesAnterior(int ano, int mes) {
    final pa = mes == 0 ? ano - 1 : ano, pm = mes == 0 ? 11 : mes - 1;
    if (!dados.anos.contains(pa)) return 0;
    final anterior = <String, double>{};
    for (final g in dados.gruposDoAno(pa)) {
      for (final i in dados.itensDo(g.id)) {
        anterior['${g.receita ? '#rec' : g.nome}|${i.nome}'] = dados.valor(i.id, pm);
      }
    }
    var n = 0;
    for (final g in dados.gruposDoAno(ano)) {
      for (final i in dados.itensDo(g.id)) {
        final pv = anterior['${g.receita ? '#rec' : g.nome}|${i.nome}'] ?? 0;
        if (dados.valor(i.id, mes) == 0 && pv != 0) {
          final lista = List<double>.of(dados.valoresDo(i.id))..[mes] = pv;
          dados.valores[i.id] = lista;
          _enfileirar('v:${i.id}:$mes', 'valores', {'item_id': i.id, 'mes': mes, 'valor': pv});
          n++;
        }
      }
    }
    if (n > 0) _mudou();
    return n;
  }

  /* ---------------- estrutura ---------------- */

  void _gravarGrupo(Grupo g) {
    dados.grupos[g.id] = g;
    _enfileirar('g:${g.id}', 'grupos', g.toRow());
  }

  void _gravarItem(Item i) {
    dados.itens[i.id] = i;
    _enfileirar('i:${i.id}', 'itens', i.toRow());
  }

  String criarGrupo(int ano, String nome, {TipoGrupo tipo = TipoGrupo.despesa}) {
    final g = Grupo(id: _novoId(), ano: ano, nome: nome.trim(), tipo: tipo, ordem: dados.proximaOrdemGrupo(ano));
    _gravarGrupo(g);
    _mudou();
    return g.id;
  }

  String criarItem(String grupoId, String nome) {
    final i = Item(id: _novoId(), grupoId: grupoId, nome: nome.trim(), ordem: dados.proximaOrdemItem(grupoId));
    _gravarItem(i);
    _mudou();
    return i.id;
  }

  /// Item de receita no ano (cria o grupo "Receitas" se ainda não existir).
  String criarReceita(int ano, String nome) {
    final g = dados.grupoReceita(ano)?.id ?? criarGrupo(ano, 'Receitas', tipo: TipoGrupo.receita);
    return criarItem(g, nome);
  }

  void renomearGrupo(String id, String nome) {
    final g = dados.grupos[id];
    if (g == null || nome.trim().isEmpty || g.nome == nome.trim()) return;
    _gravarGrupo(g.copyWith(nome: nome.trim()));
    _mudou();
  }

  void definirInvestimento(String id, bool investimento) {
    final g = dados.grupos[id];
    if (g == null || g.receita) return;
    _gravarGrupo(g.copyWith(tipo: investimento ? TipoGrupo.investimento : TipoGrupo.despesa));
    _mudou();
  }

  void renomearItem(String id, String nome) {
    final i = dados.itens[id];
    if (i == null || nome.trim().isEmpty || i.nome == nome.trim()) return;
    _gravarItem(i.copyWith(nome: nome.trim()));
    _mudou();
  }

  /// Move o grupo uma posição (direcao -1 = sobe, +1 = desce) entre os grupos de despesa do ano.
  void moverGrupo(String id, int direcao) {
    final g = dados.grupos[id];
    if (g == null) return;
    final lista = dados.gruposDespesa(g.ano);
    final i = lista.indexWhere((x) => x.id == id), j = i + direcao;
    if (i < 0 || j < 0 || j >= lista.length) return;
    lista.insert(j, lista.removeAt(i));
    for (var k = 0; k < lista.length; k++) {
      if (lista[k].ordem != k + 1) _gravarGrupo(lista[k].copyWith(ordem: k + 1.0));
    }
    _mudou();
  }

  void moverItem(String id, int direcao) {
    final it = dados.itens[id];
    if (it == null) return;
    final lista = dados.itensDo(it.grupoId);
    final i = lista.indexWhere((x) => x.id == id), j = i + direcao;
    if (i < 0 || j < 0 || j >= lista.length) return;
    lista.insert(j, lista.removeAt(i));
    for (var k = 0; k < lista.length; k++) {
      if (lista[k].ordem != k + 1) _gravarItem(lista[k].copyWith(ordem: k + 1.0));
    }
    _mudou();
  }

  void excluirGrupo(String id) {
    final g = dados.grupos[id];
    if (g == null) return;
    for (final i in dados.itensDo(id)) {
      _gravarItem(i.copyWith(excluido: true));
    }
    _gravarGrupo(g.copyWith(excluido: true));
    _mudou();
  }

  void excluirItem(String id) {
    final i = dados.itens[id];
    if (i == null) return;
    _gravarItem(i.copyWith(excluido: true));
    _mudou();
  }

  /// Cria o ano copiando grupos e itens de [base] (valores zerados). Sem base, usa a estrutura padrão.
  void criarAno(int ano, {int? base}) {
    if (dados.anos.contains(ano)) return;
    final origem = base != null && dados.anos.contains(base) ? base : null;
    if (origem == null) {
      _estruturaPadrao(ano);
    } else {
      for (final g in dados.gruposDoAno(origem)) {
        final ng = Grupo(id: _novoId(), ano: ano, nome: g.nome, tipo: g.tipo, ordem: g.ordem);
        _gravarGrupo(ng);
        for (final i in dados.itensDo(g.id)) {
          _gravarItem(Item(id: _novoId(), grupoId: ng.id, nome: i.nome, ordem: i.ordem));
        }
      }
      if (dados.grupoReceita(ano) == null) {
        _gravarGrupo(Grupo(id: _novoId(), ano: ano, nome: 'Receitas', tipo: TipoGrupo.receita, ordem: 0));
      }
    }
    _mudou();
  }

  void excluirAno(int ano) {
    if (dados.anos.length < 2) return;
    for (final g in dados.gruposDoAno(ano)) {
      for (final i in dados.itensDo(g.id)) {
        _gravarItem(i.copyWith(excluido: true));
      }
      _gravarGrupo(g.copyWith(excluido: true));
    }
    _mudou();
  }

  void definirMeta(double pct) {
    dados.metaPct = pct;
    _enfileirar('lar', 'lares', {'meta_pct': pct});
    _mudou();
  }

  void _estruturaPadrao(int ano) {
    var og = 0.0;
    void grupo(String nome, List<String> itens, [TipoGrupo tipo = TipoGrupo.despesa]) {
      final g = Grupo(id: _novoId(), ano: ano, nome: nome, tipo: tipo, ordem: og++);
      _gravarGrupo(g);
      var oi = 1.0;
      for (final n in itens) {
        _gravarItem(Item(id: _novoId(), grupoId: g.id, nome: n, ordem: oi++));
      }
    }

    grupo('Receitas', ['Breno', 'Jaqueline'], TipoGrupo.receita);
    grupo('Cartão de Crédito/Empréstimos', ['Nubank Breno', 'C6', 'BB', 'Shopee Breno', 'BB - Empréstimo Breno', 'Nubank Jaqueline', 'Shopee Jaqueline']);
    grupo('Pessoas', ['Pai', 'Marco Antônio']);
    grupo('Casa Valparaíso', ['Financiamento', 'Água', 'Energia', 'Condomínio', 'Manutenção']);
    grupo('Casa Candangolândia', ['Aluguel', 'Água', 'Energia', 'Internet', 'Manutenção']);
    grupo('Carro', ['Lavagem', 'Combustível', 'Manutenção 10km', 'Pai - Regularização Carro', 'Josely - Regularização Carro']);
    grupo('Mercado/Alimentação', ['Compra do Mês']);
    grupo('Investimentos/Reserva', ['Nubank Caixinha/Limite Garantido'], TipoGrupo.investimento);
    grupo('Entretenimento', ['Yudi - Jogo', 'Águas Correntes - Entrada']);
    grupo('Diversos', ['Internet Móvel Celular Breno', 'Geladeira Niva', 'Material Escolar Yudi', 'DAS']);
  }

  /* ---------------- backup (compatível com o PWA antigo) ---------------- */

  /// Exporta no mesmo formato do backup .json do PWA (years → receitas/grupos/itens/valores).
  Map<String, dynamic> exportarBackup() {
    final years = <String, dynamic>{};
    for (final ano in dados.anos) {
      final rec = dados.grupoReceita(ano);
      years['$ano'] = {
        'receitaGroup': {'id': rec?.id ?? '', 'nome': rec?.nome ?? 'Receitas'},
        'receitas': [for (final i in dados.receitasDo(ano)) _itemJson(i)],
        'grupos': [
          for (final g in dados.gruposDespesa(ano))
            {'id': g.id, 'nome': g.nome, 'investimento': g.investimento, 'itens': [for (final i in dados.itensDo(g.id)) _itemJson(i)]},
        ],
      };
    }
    return {'app': 'controle-financeiro', 'version': 1, 'updatedAt': DateTime.now().millisecondsSinceEpoch, 'metaPct': dados.metaPct, 'years': years};
  }

  Map<String, dynamic> _itemJson(Item i) => {'id': i.id, 'nome': i.nome, 'valores': dados.valoresDo(i.id)};

  /// Substitui todos os dados do lar pelo backup do PWA. Os IDs antigos não são usados (o servidor usa UUID).
  /// Lança [FormatException] se o arquivo não for um backup válido.
  void importarBackup(Map<String, dynamic> j) {
    final years = j['years'];
    if (years is! Map || years.isEmpty) throw const FormatException('Arquivo de backup inválido');
    // Apaga (logicamente) tudo o que existe.
    for (final g in dados.grupos.values.where((g) => !g.excluido).toList()) {
      _gravarGrupo(g.copyWith(excluido: true));
    }
    for (final i in dados.itens.values.where((i) => !i.excluido).toList()) {
      _gravarItem(i.copyWith(excluido: true));
    }
    void itens(String grupoId, Object? lista) {
      var o = 1.0;
      for (final raw in (lista as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final it = Item(id: _novoId(), grupoId: grupoId, nome: '${m['nome'] ?? ''}', ordem: o++);
        _gravarItem(it);
        final vs = fix12(m['valores'] as List?);
        dados.valores[it.id] = vs;
        for (var mes = 0; mes < 12; mes++) {
          if (vs[mes] != 0) _enfileirar('v:${it.id}:$mes', 'valores', {'item_id': it.id, 'mes': mes, 'valor': vs[mes]});
        }
      }
    }

    years.forEach((k, raw) {
      final ano = int.tryParse('$k');
      if (ano == null || raw is! Map) return;
      final y = Map<String, dynamic>.from(raw);
      final rg = (y['receitaGroup'] as Map?) ?? const {};
      final rec = Grupo(id: _novoId(), ano: ano, nome: '${rg['nome'] ?? 'Receitas'}', tipo: TipoGrupo.receita, ordem: 0);
      _gravarGrupo(rec);
      itens(rec.id, y['receitas']);
      var o = 1.0;
      for (final gr in (y['grupos'] as List? ?? const [])) {
        final gm = Map<String, dynamic>.from(gr as Map);
        final g = Grupo(
          id: _novoId(),
          ano: ano,
          nome: '${gm['nome'] ?? ''}',
          tipo: gm['investimento'] == true ? TipoGrupo.investimento : TipoGrupo.despesa,
          ordem: o++,
        );
        _gravarGrupo(g);
        itens(g.id, gm['itens']);
      }
    });
    final meta = j['metaPct'];
    if (meta is num) definirMeta(meta.toDouble());
    _mudou();
  }
}

/* ---------------- erros ---------------- */

/// Sem internet ou servidor inalcançável (inclui falha ao renovar a sessão sem conexão).
bool pareceOffline(Object e) {
  final s = '${e.runtimeType} $e';
  return RegExp(r'SocketException|ClientException|TimeoutException|HandshakeException|Failed host lookup|Connection (refused|reset|closed|failed)|Network is unreachable|AuthRetryableFetchException',
          caseSensitive: false)
      .hasMatch(s);
}

String mensagemDeErro(Object e) {
  final s = '$e';
  if (s.contains('42501') || s.contains('row-level security')) return 'Sem permissão para gravar neste lar.';
  if (s.contains('JWT expired')) return 'Renovando a sessão… tentando de novo em instantes.';
  if (s.contains('refresh_token') || s.contains('Invalid Refresh Token')) return 'Sessão encerrada. Saia e entre de novo.';
  return 'Não foi possível sincronizar: $s';
}
