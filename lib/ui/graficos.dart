import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/modelo.dart';
import 'app.dart';
import 'comum.dart';
import 'formato.dart';
import 'tema.dart';

/// Gráficos do ano, desenhados à mão (sem biblioteca), como no PWA.
class TelaGraficos extends StatefulWidget {
  const TelaGraficos({super.key, required this.ano, required this.largo});
  final int ano;
  final bool largo;
  @override
  State<TelaGraficos> createState() => _TelaGraficosState();
}

class _TelaGraficosState extends State<TelaGraficos> {
  int? _mes1, _mes2;

  @override
  Widget build(BuildContext context) {
    final d = RepoScope.of(context).dados;
    final c = CalcAno.de(d, widget.ano);
    final cores = Cores.of(context);
    final t = Theme.of(context);

    final porGrupo = [for (final (g, tot) in c.grupos) (g, soma(tot))]..sort((a, b) => b.$2.compareTo(a.$2));
    final maxG = porGrupo.isEmpty ? 1.0 : math.max(1.0, porGrupo.first.$2);

    Widget legenda(List<(String, Color)> itens) => Wrap(spacing: 14, runSpacing: 4, children: [
          for (final (n, cor) in itens)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Text(n, style: t.textTheme.bodySmall),
            ]),
        ]);

    Widget detalhe(int? m, List<(String, double)> Function(int) linhas) => m == null
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Toque num mês para ver os valores.', style: t.textTheme.bodySmall),
          )
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(capitalizar(meses[m]), style: t.textTheme.titleSmall),
              for (final (r, v) in linhas(m)) LinhaValor(r, v),
            ]),
          );

    final totais = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(child: _Destaque('Receitas do ano', soma(c.receitas), cores.receita)),
          Expanded(child: _Destaque('Despesas do ano', soma(c.despesas), cores.despesa)),
        ]),
      ),
    );

    final g1 = _Bloco(
      titulo: 'Receitas × Despesas e Investimentos',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        legenda([('Receitas', cores.receita), ('Gasto real', cores.despesa), ('Investimentos', cores.invest)]),
        const SizedBox(height: 8),
        _GraficoMeses(
          calc: c,
          empilhado: false,
          selecionado: _mes1,
          aoTocar: (m) => setState(() => _mes1 = m),
        ),
        detalhe(_mes1, (m) => [
              ('Receitas', c.receitas[m]),
              ('Gasto real', c.gastoReal[m]),
              ('Investimentos', c.invest[m]),
              ('Despesas (total)', c.despesas[m]),
            ]),
      ]),
    );

    final g2 = _Bloco(
      titulo: 'Receitas, despesas e investimentos por mês',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        legenda([('Sobra de receita', cores.receita), ('Gasto real', cores.despesa), ('Investimentos', cores.invest)]),
        const SizedBox(height: 8),
        _GraficoMeses(
          calc: c,
          empilhado: true,
          selecionado: _mes2,
          aoTocar: (m) => setState(() => _mes2 = m),
        ),
        detalhe(_mes2, (m) => [
              ('Receitas', c.receitas[m]),
              ('Gasto real', c.gastoReal[m]),
              ('Investimentos', c.invest[m]),
              ('Sobra', math.max(0, c.receitas[m] - c.despesas[m]).toDouble()),
            ]),
      ]),
    );

    final g3 = _Bloco(
      titulo: 'Despesas por grupo em ${widget.ano}',
      child: c.mesesComLancamento == 0
          ? const Padding(padding: EdgeInsets.all(8), child: Text('Sem lançamentos neste ano.'))
          : Column(children: [
              for (final (g, v) in porGrupo)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(g.nome, style: t.textTheme.bodySmall)),
                      Text(brl(v), style: t.textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    ]),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (v / maxG).clamp(0.0, 1.0).toDouble(),
                        minHeight: 8,
                        color: g.investimento ? cores.invest : cores.despesa,
                        backgroundColor: t.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ]),
                ),
            ]),
    );

    if (widget.largo) {
      return Largura(
        max: 1300,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          totais,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: g1),
            const SizedBox(width: 12),
            Expanded(child: g2),
          ]),
          g3,
        ]),
      );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [totais, g1, g2, g3]);
  }
}

class _Destaque extends StatelessWidget {
  const _Destaque(this.rotulo, this.valor, this.cor);
  final String rotulo;
  final double valor;
  final Color cor;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Flexible(child: Text(rotulo, style: t.textTheme.bodySmall)),
      ]),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(brl(valor), style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

class _Bloco extends StatelessWidget {
  const _Bloco({required this.titulo, required this.child});
  final String titulo;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TituloSecao(titulo),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: child)),
      ]);
}

/// Barras por mês. [empilhado]=false: receitas ao lado de gasto real + investimentos.
/// [empilhado]=true: investimentos, gasto real e sobra de receita empilhados.
class _GraficoMeses extends StatelessWidget {
  const _GraficoMeses({required this.calc, required this.empilhado, required this.selecionado, required this.aoTocar});
  final CalcAno calc;
  final bool empilhado;
  final int? selecionado;
  final ValueChanged<int> aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = empilhado ? 240.0 : 210.0;
      final p = _Pintor(
        calc: calc,
        empilhado: empilhado,
        selecionado: selecionado,
        cores: Cores.of(context),
        texto: t.textTheme.labelSmall!.copyWith(color: t.colorScheme.onSurfaceVariant),
        grade: t.colorScheme.outlineVariant,
        realce: t.colorScheme.primary.withValues(alpha: 0.08),
      );
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (e) {
          final m = p.mesEm(e.localPosition.dx, w);
          if (m != null) aoTocar(m);
        },
        child: Semantics(
          label: empilhado ? 'Gráfico empilhado de receitas, despesas e investimentos por mês' : 'Gráfico de receitas, gasto real e investimentos por mês',
          child: CustomPaint(size: Size(w, h), painter: p),
        ),
      );
    });
  }
}

class _Pintor extends CustomPainter {
  _Pintor({
    required this.calc,
    required this.empilhado,
    required this.selecionado,
    required this.cores,
    required this.texto,
    required this.grade,
    required this.realce,
  });
  final CalcAno calc;
  final bool empilhado;
  final int? selecionado;
  final Cores cores;
  final TextStyle texto;
  final Color grade, realce;

  static const _esq = 44.0, _dir = 6.0, _topo = 8.0, _base = 22.0;

  int? mesEm(double x, double largura) {
    final bw = (largura - _esq - _dir) / 12;
    final m = ((x - _esq) / bw).floor();
    return m >= 0 && m < 12 ? m : null;
  }

  static double _teto(double v) {
    if (v <= 0) return 1;
    final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final k in const <double>[1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]) {
      if (k * p >= v) return k * p;
    }
    return 10 * p;
  }

  void _texto(Canvas canvas, String s, Offset pos, {TextAlign alinhamento = TextAlign.center}) {
    final tp = TextPainter(text: TextSpan(text: s, style: texto), textDirection: TextDirection.ltr)..layout();
    final dx = switch (alinhamento) {
      TextAlign.right => pos.dx - tp.width,
      TextAlign.center => pos.dx - tp.width / 2,
      _ => pos.dx,
    };
    tp.paint(canvas, Offset(dx, pos.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final iw = size.width - _esq - _dir, ih = size.height - _topo - _base, bw = iw / 12;
    final c = calc;
    final maximo = empilhado
        ? [for (var m = 0; m < 12; m++) math.max(c.receitas[m], c.despesas[m])].reduce(math.max)
        : [...c.receitas, ...c.despesas].reduce(math.max);
    final teto = _teto(math.max(maximo, 100.0));
    double y(double v) => _topo + ih * (1 - v / teto);

    final linha = Paint()
      ..color = grade
      ..strokeWidth = 1;
    for (final f in const [1.0, 0.75, 0.5, 0.25, 0.0]) {
      final v = teto * f;
      canvas.drawLine(Offset(_esq, y(v)), Offset(size.width - _dir, y(v)), linha..strokeWidth = f == 0 ? 1.4 : 0.6);
      _texto(canvas, curto(v), Offset(_esq - 6, y(v)), alinhamento: TextAlign.right);
    }

    final pinta = Paint();
    void barra(double x, double v0, double v1, double w, Color cor) {
      if (v1 - v0 <= 0) return;
      final r = Rect.fromLTRB(x, y(v1), x + w, y(v0));
      if (r.height < 0.5) return;
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(math.min(2.5, w / 2))), pinta..color = cor);
    }

    for (var m = 0; m < 12; m++) {
      final x0 = _esq + m * bw;
      if (m == selecionado) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x0, _topo, bw, ih), const Radius.circular(4)),
          Paint()..color = realce,
        );
      }
      if (empilhado) {
        final w = math.min(18.0, bw * 0.7), x = x0 + (bw - w) / 2;
        final sobra = math.max(0.0, c.receitas[m] - c.despesas[m]);
        var base = 0.0;
        for (final (v, cor) in [(c.invest[m], cores.invest), (c.gastoReal[m], cores.despesa), (sobra, cores.receita)]) {
          if (v <= 0) continue;
          barra(x, base, base + v, w, cor);
          base += v;
        }
      } else {
        final w = math.min(10.0, bw * 0.34), gap = 2.0;
        final xa = x0 + bw / 2 - w - gap / 2, xb = x0 + bw / 2 + gap / 2;
        barra(xa, 0, c.receitas[m], w, cores.receita);
        final gr = math.max(0.0, c.gastoReal[m]), inv = math.max(0.0, c.invest[m]);
        barra(xb, 0, gr, w, cores.despesa);
        barra(xb, gr, gr + inv, w, cores.invest);
      }
      _texto(canvas, mesesAbrev[m], Offset(x0 + bw / 2, size.height - _base / 2 + 2));
    }
  }

  @override
  bool shouldRepaint(_Pintor old) =>
      old.calc != calc || old.selecionado != selecionado || old.cores != cores || old.texto != texto || old.empilhado != empilhado;
}
