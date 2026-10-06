/// Modelo de dados (igual às tabelas do Supabase) e cálculos do resumo.
library;

const meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];
const mesesAbrev = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

enum TipoGrupo {
  receita,
  despesa,
  investimento;

  static TipoGrupo parse(Object? s) =>
      TipoGrupo.values.firstWhere((t) => t.name == s, orElse: () => TipoGrupo.despesa);
}

double round2(num n) => (n * 100).roundToDouble() / 100;
double soma(Iterable<num> v) => v.fold<double>(0, (a, b) => a + b);
List<double> zeros() => List<double>.filled(12, 0);

class Grupo {
  final String id;
  final int ano;
  final String nome;
  final TipoGrupo tipo;
  final double ordem;
  final bool excluido;

  const Grupo({
    required this.id,
    required this.ano,
    required this.nome,
    required this.tipo,
    required this.ordem,
    this.excluido = false,
  });

  bool get investimento => tipo == TipoGrupo.investimento;
  bool get receita => tipo == TipoGrupo.receita;

  Grupo copyWith({String? nome, TipoGrupo? tipo, double? ordem, bool? excluido}) => Grupo(
        id: id,
        ano: ano,
        nome: nome ?? this.nome,
        tipo: tipo ?? this.tipo,
        ordem: ordem ?? this.ordem,
        excluido: excluido ?? this.excluido,
      );

  /// Linha para o Supabase (sem lar_id: quem envia acrescenta).
  Map<String, dynamic> toRow() =>
      {'id': id, 'ano': ano, 'nome': nome, 'tipo': tipo.name, 'ordem': ordem, 'excluido': excluido};

  factory Grupo.fromRow(Map<String, dynamic> r) => Grupo(
        id: r['id'] as String,
        ano: (r['ano'] as num).toInt(),
        nome: (r['nome'] ?? '') as String,
        tipo: TipoGrupo.parse(r['tipo']),
        ordem: (r['ordem'] as num?)?.toDouble() ?? 0,
        excluido: r['excluido'] == true,
      );
}

class Item {
  final String id;
  final String grupoId;
  final String nome;
  final double ordem;
  final bool excluido;

  const Item({required this.id, required this.grupoId, required this.nome, required this.ordem, this.excluido = false});

  Item copyWith({String? nome, double? ordem, bool? excluido}) => Item(
        id: id,
        grupoId: grupoId,
        nome: nome ?? this.nome,
        ordem: ordem ?? this.ordem,
        excluido: excluido ?? this.excluido,
      );

  Map<String, dynamic> toRow() => {'id': id, 'grupo_id': grupoId, 'nome': nome, 'ordem': ordem, 'excluido': excluido};

  factory Item.fromRow(Map<String, dynamic> r) => Item(
        id: r['id'] as String,
        grupoId: r['grupo_id'] as String,
        nome: (r['nome'] ?? '') as String,
        ordem: (r['ordem'] as num?)?.toDouble() ?? 0,
        excluido: r['excluido'] == true,
      );
}

/// Todos os dados de um lar, como ficam guardados no aparelho.
class Dados {
  final Map<String, Grupo> grupos;
  final Map<String, Item> itens;
  /// itemId → 12 valores (jan..dez).
  final Map<String, List<double>> valores;
  double metaPct;

  Dados({Map<String, Grupo>? grupos, Map<String, Item>? itens, Map<String, List<double>>? valores, this.metaPct = 30})
      : grupos = grupos ?? {},
        itens = itens ?? {},
        valores = valores ?? {};

  List<int> get anos {
    final s = grupos.values.where((g) => !g.excluido).map((g) => g.ano).toSet().toList()..sort();
    return s;
  }

  List<Grupo> gruposDoAno(int ano) =>
      grupos.values.where((g) => !g.excluido && g.ano == ano).toList()..sort(_porOrdem);

  /// Grupos de despesa e investimento, na ordem da tela.
  List<Grupo> gruposDespesa(int ano) => gruposDoAno(ano).where((g) => !g.receita).toList();

  /// O grupo de receitas do ano (o primeiro, se houver mais de um).
  Grupo? grupoReceita(int ano) {
    for (final g in gruposDoAno(ano)) {
      if (g.receita) return g;
    }
    return null;
  }

  /// Todos os grupos de receita do ano (normalmente um só).
  List<Grupo> gruposReceita(int ano) => gruposDoAno(ano).where((g) => g.receita).toList();

  List<Item> itensDo(String grupoId) =>
      itens.values.where((i) => !i.excluido && i.grupoId == grupoId).toList()..sort(_porOrdemItem);

  List<Item> receitasDo(int ano) => [for (final g in gruposReceita(ano)) ...itensDo(g.id)];

  double valor(String itemId, int mes) => valores[itemId]?[mes] ?? 0;
  List<double> valoresDo(String itemId) => valores[itemId] ?? zeros();

  double proximaOrdemGrupo(int ano) {
    final gs = grupos.values.where((g) => g.ano == ano);
    return gs.isEmpty ? 1 : gs.map((g) => g.ordem).reduce((a, b) => a > b ? a : b) + 1;
  }

  double proximaOrdemItem(String grupoId) {
    final its = itens.values.where((i) => i.grupoId == grupoId);
    return its.isEmpty ? 1 : its.map((i) => i.ordem).reduce((a, b) => a > b ? a : b) + 1;
  }

  static int _porOrdem(Grupo a, Grupo b) {
    final c = a.ordem.compareTo(b.ordem);
    return c != 0 ? c : a.nome.compareTo(b.nome);
  }

  static int _porOrdemItem(Item a, Item b) {
    final c = a.ordem.compareTo(b.ordem);
    return c != 0 ? c : a.nome.compareTo(b.nome);
  }

  Map<String, dynamic> toJson() => {
        'metaPct': metaPct,
        'grupos': [for (final g in grupos.values) g.toRow()],
        'itens': [for (final i in itens.values) i.toRow()],
        'valores': {for (final e in valores.entries) e.key: e.value},
      };

  factory Dados.fromJson(Map<String, dynamic> j) {
    final d = Dados(metaPct: (j['metaPct'] as num?)?.toDouble() ?? 30);
    for (final r in (j['grupos'] as List? ?? const [])) {
      final g = Grupo.fromRow(Map<String, dynamic>.from(r as Map));
      d.grupos[g.id] = g;
    }
    for (final r in (j['itens'] as List? ?? const [])) {
      final i = Item.fromRow(Map<String, dynamic>.from(r as Map));
      d.itens[i.id] = i;
    }
    final vs = (j['valores'] as Map?) ?? const {};
    vs.forEach((k, v) => d.valores[k as String] = fix12(v as List?));
    return d;
  }
}

List<double> fix12(List? v) {
  final a = zeros();
  if (v == null) return a;
  for (var i = 0; i < v.length && i < 12; i++) {
    final x = v[i];
    a[i] = x is num ? x.toDouble() : double.tryParse('$x') ?? 0;
  }
  return a;
}

/// Totais do ano — mesmas regras da planilha original:
/// Despesas incluem investimentos; Gasto real = Despesas − Investimentos.
class CalcAno {
  final List<double> receitas, despesas, invest, gastoReal, saldo, meta, recMenosInv;
  final List<(Grupo, List<double>)> grupos;

  CalcAno._(this.receitas, this.despesas, this.invest, this.gastoReal, this.saldo, this.meta, this.recMenosInv, this.grupos);

  factory CalcAno.de(Dados d, int ano) {
    final rec = zeros(), desp = zeros(), inv = zeros();
    final porGrupo = <(Grupo, List<double>)>[];
    for (final g in d.gruposDespesa(ano)) {
      final tot = zeros();
      for (final i in d.itensDo(g.id)) {
        final v = d.valoresDo(i.id);
        for (var m = 0; m < 12; m++) {
          tot[m] += v[m];
        }
      }
      for (var m = 0; m < 12; m++) {
        desp[m] += tot[m];
        if (g.investimento) inv[m] += tot[m];
      }
      porGrupo.add((g, tot.map(round2).toList()));
    }
    for (final i in d.receitasDo(ano)) {
      final v = d.valoresDo(i.id);
      for (var m = 0; m < 12; m++) {
        rec[m] += v[m];
      }
    }
    final r = rec.map(round2).toList(), dd = desp.map(round2).toList(), iv = inv.map(round2).toList();
    List<double> f(double Function(int m) fn) => List.generate(12, (m) => round2(fn(m)));
    return CalcAno._(
      r,
      dd,
      iv,
      f((m) => dd[m] - iv[m]),
      f((m) => r[m] - dd[m]),
      f((m) => r[m] * d.metaPct / 100),
      f((m) => r[m] - iv[m]),
      porGrupo,
    );
  }

  /// Meses com receita ou despesa ≠ 0 — base da média.
  int get mesesComLancamento {
    var n = 0;
    for (var m = 0; m < 12; m++) {
      if (receitas[m] != 0 || despesas[m] != 0) n++;
    }
    return n;
  }

  double media(List<double> v) {
    final n = mesesComLancamento;
    return n == 0 ? 0 : round2(soma(v) / n);
  }
}

/// Converte texto digitado em número. Aceita "1.234,56", "1234.56", "R$ 10" e contas: "100+50,5-20".
/// Retorna null se inválido.
double? parseMoney(String text) {
  final s = text.replaceAll(RegExp(r'R\$|\s'), '');
  if (s.isEmpty) return 0;
  final partes = RegExp(r'[+-]?[^+-]+').allMatches(s).map((m) => m.group(0)!).toList();
  if (partes.isEmpty) return null;
  var total = 0.0;
  for (var p in partes) {
    var sinal = 1;
    if (p.startsWith('-')) {
      sinal = -1;
      p = p.substring(1);
    } else if (p.startsWith('+')) {
      p = p.substring(1);
    }
    if (p.contains(',')) {
      p = p.replaceAll('.', '').replaceAll(',', '.');
    } else if ('.'.allMatches(p).length > 1 || RegExp(r'\.\d{3}$').hasMatch(p)) {
      p = p.replaceAll('.', '');
    }
    final v = double.tryParse(p);
    if (v == null) return null;
    total += sinal * v;
  }
  return round2(total);
}
