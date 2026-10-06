import 'package:flutter/material.dart';

import '../data/modelo.dart';
import 'app.dart';
import 'comum.dart';
import 'formato.dart';

class _Linha {
  const _Linha(this.rotulo, this.valores, {this.forte = false, this.colorir = false});
  final String rotulo;
  final List<double> valores;
  final bool forte, colorir;
}

/// Tabela anual: Resumo (igual à aba da planilha), Receitas e cada grupo, com total e média.
class TelaResumo extends StatefulWidget {
  const TelaResumo({super.key, required this.ano});
  final int ano;
  @override
  State<TelaResumo> createState() => _TelaResumoState();
}

class _TelaResumoState extends State<TelaResumo> {
  String _visao = 'resumo';

  @override
  Widget build(BuildContext context) {
    final d = RepoScope.of(context).dados;
    final c = CalcAno.de(d, widget.ano);
    final grupos = d.gruposDespesa(widget.ano);
    final visoes = [('resumo', 'Resumo'), ('receitas', 'Receitas'), for (final g in grupos) (g.id, g.nome)];
    if (!visoes.any((v) => v.$1 == _visao)) _visao = 'resumo';

    late final String titulo;
    late final List<_Linha> linhas;
    if (_visao == 'resumo') {
      titulo = 'Resumo';
      linhas = [
        _Linha('Receitas', c.receitas, forte: true),
        _Linha('${pct(d.metaPct)}% da receita', c.meta),
        _Linha('Receitas − Investimentos', c.recMenosInv),
        for (final (g, tot) in c.grupos) _Linha(g.nome, tot),
        _Linha('Despesas', c.despesas, forte: true),
        _Linha('Despesas − Investimentos', c.gastoReal),
        _Linha('Receitas − Despesas', c.saldo, forte: true, colorir: true),
      ];
    } else if (_visao == 'receitas') {
      titulo = 'Receitas';
      linhas = [
        for (final i in d.receitasDo(widget.ano)) _Linha(i.nome, d.valoresDo(i.id)),
        _Linha('TOTAL MÊS', c.receitas, forte: true),
      ];
    } else {
      final (g, tot) = c.grupos.firstWhere((e) => e.$1.id == _visao);
      titulo = g.nome;
      linhas = [
        for (final i in d.itensDo(g.id)) _Linha(i.nome, d.valoresDo(i.id)),
        _Linha('TOTAL MÊS', tot, forte: true),
      ];
    }

    final n = c.mesesComLancamento;
    return Largura(
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final v in visoes)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(v.$2),
                  selected: v.$1 == _visao,
                  onSelected: (_) => setState(() => _visao = v.$1),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: _Tabela(titulo: titulo, linhas: linhas, calc: c, ano: widget.ano),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'Média = total ÷ meses com lançamento ($n ${n == 1 ? 'mês' : 'meses'}). Role a tabela para o lado.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ]),
    );
  }
}

class _Tabela extends StatelessWidget {
  const _Tabela({required this.titulo, required this.linhas, required this.calc, required this.ano});
  final String titulo;
  final List<_Linha> linhas;
  final CalcAno calc;
  final int ano;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hoje = DateTime.now();
    final atual = ano == hoje.year ? hoje.month - 1 : -1;
    const tab = [FontFeature.tabularFigures()];
    final realce = t.colorScheme.primary.withValues(alpha: 0.08);

    Widget celula(String s, {bool numero = true, bool forte = false, Color? cor, Color? fundo, double largura = 92}) => Container(
          width: largura,
          color: fundo,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          alignment: numero ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            s,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.bodySmall?.copyWith(fontFeatures: tab, fontWeight: forte ? FontWeight.w600 : null, color: cor),
          ),
        );

    Color? corDe(_Linha l, double v) =>
        l.colorir ? corSaldo(context, v) : (v == 0 ? t.colorScheme.onSurfaceVariant.withValues(alpha: 0.5) : null);

    final cabecalho = Container(
      color: t.colorScheme.surfaceContainerHighest,
      child: Row(children: [
        for (var m = 0; m < 12; m++) celula(mesesAbrev[m], forte: true, fundo: m == atual ? realce : null),
        celula('Total ano', forte: true, largura: 110),
        celula('Média', forte: true, largura: 100),
      ]),
    );

    final corpo = [
      for (final l in linhas)
        Row(children: [
          for (var m = 0; m < 12; m++)
            celula(num2(l.valores[m]), forte: l.forte, cor: corDe(l, l.valores[m]), fundo: m == atual ? realce : null),
          celula(num2(soma(l.valores)), forte: true, cor: l.colorir ? corSaldo(context, soma(l.valores)) : null, largura: 110),
          celula(num2(calc.media(l.valores)), largura: 100),
        ]),
    ];

    // Primeira coluna fixa; as colunas dos meses rolam para o lado.
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          color: t.colorScheme.surfaceContainerHighest,
          child: celula(titulo, numero: false, forte: true, largura: 170),
        ),
        for (final l in linhas) celula(l.rotulo, numero: false, forte: l.forte, largura: 170),
      ]),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [cabecalho, ...corpo]),
        ),
      ),
    ]);
  }
}
