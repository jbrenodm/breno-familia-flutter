import 'package:flutter/material.dart';

import '../data/modelo.dart';
import 'app.dart';
import 'comum.dart';
import 'formato.dart';
import 'tema.dart';

/// Valor de cada item no mês, agrupado, e os totais do mês.
class TelaMes extends StatelessWidget {
  const TelaMes({super.key, required this.ano, required this.mes});
  final int ano, mes;

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final d = repo.dados;
    final c = CalcAno.de(d, ano);
    final cores = Cores.of(context);
    final largo = MediaQuery.sizeOf(context).width >= 840;

    final resumo = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Saldo do mês (Receitas − Despesas)', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(brl(c.saldo[mes]),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: corSaldo(context, c.saldo[mes]),
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
          const Divider(height: 20),
          LinhaValor('Receitas', c.receitas[mes], ponto: cores.receita),
          LinhaValor('Despesas (total)', c.despesas[mes]),
          LinhaValor('Gasto real', c.gastoReal[mes], ponto: cores.despesa),
          LinhaValor('Investimentos', c.invest[mes], ponto: cores.invest),
          LinhaValor('Receitas − Investimentos', c.recMenosInv[mes]),
          LinhaValor('${pct(d.metaPct)}% da receita', c.meta[mes]),
        ]),
      ),
    );

    final receitas = d.receitasDo(ano);
    final grupos = d.gruposDespesa(ano);
    final porId = {for (final (g, tot) in c.grupos) g.id: tot};

    final lista = <Widget>[
      const TituloSecao('Receitas'),
      _CartaoGrupo(
        chave: 'rec-$ano',
        nome: 'Receitas',
        totalMes: c.receitas[mes],
        totalAno: soma(c.receitas),
        itens: receitas,
        mes: mes,
      ),
      const TituloSecao('Despesas'),
      for (final g in grupos)
        _CartaoGrupo(
          chave: g.id,
          nome: g.nome,
          investimento: g.investimento,
          totalMes: porId[g.id]?[mes] ?? 0,
          totalAno: soma(porId[g.id] ?? const []),
          itens: d.itensDo(g.id),
          mes: mes,
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: const Icon(Icons.content_copy_outlined),
        label: const Text('Copiar valores do mês anterior (só itens zerados)'),
        onPressed: () async {
          final pm = mes == 0 ? 11 : mes - 1, pa = mes == 0 ? ano - 1 : ano;
          final ok = await confirmar(context, 'Copiar do mês anterior?',
              'Itens com valor zero em ${meses[mes]} receberão o valor de ${meses[pm]}/$pa. Valores já preenchidos não mudam.',
              ok: 'Copiar');
          if (!ok || !context.mounted) return;
          final n = repo.copiarMesAnterior(ano, mes);
          avisar(context, n > 0 ? '$n valor(es) copiado(s)' : 'Nada para copiar');
        },
      ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Text('Dica: no valor você pode digitar contas, ex.: 120+35,90.',
            style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
      ),
    ];

    if (largo) {
      // Windows: resumo fixo à esquerda, lançamentos à direita.
      return Largura(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 340, child: ListView(padding: const EdgeInsets.all(12), children: [resumo])),
          Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(0, 0, 12, 24), children: lista)),
        ]),
      );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [resumo, ...lista]);
  }
}

class _CartaoGrupo extends StatelessWidget {
  const _CartaoGrupo({
    required this.chave,
    required this.nome,
    required this.totalMes,
    required this.totalAno,
    required this.itens,
    required this.mes,
    this.investimento = false,
  });
  final String chave, nome;
  final double totalMes, totalAno;
  final List<Item> itens;
  final int mes;
  final bool investimento;

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.ler(context);
    final t = Theme.of(context);
    const tab = [FontFeature.tabularFigures()];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('grupo-$chave'),
        shape: const Border(),
        title: Row(children: [
          Flexible(child: Text(nome, overflow: TextOverflow.ellipsis)),
          if (investimento) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: Cores.of(context).invest.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
              child: Text('invest.', style: t.textTheme.labelSmall),
            ),
          ],
        ]),
        trailing: Text(brl(totalMes), style: t.textTheme.titleSmall?.copyWith(fontFeatures: tab)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
        children: [
          if (itens.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text('Nenhum item. Adicione em Ajustes.')),
          for (final i in itens)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(i.nome.isEmpty ? '(sem nome)' : i.nome)),
                CampoValor(
                  // PageStorageKey: sem ela, a rolagem interna do TextField lê o estado (bool) do ExpansionTile.
                  key: PageStorageKey('v-${i.id}-$mes'),
                  valor: repo.dados.valor(i.id, mes),
                  pendente: repo.estaPendente(i.id, mes),
                  rotulo: i.nome,
                  aoMudar: (v) => repo.definirValor(i.id, mes, v),
                ),
              ]),
            ),
          const Divider(),
          Row(children: [
            Expanded(child: Text('Total no ano', style: t.textTheme.bodySmall)),
            Text(brl(totalAno), style: t.textTheme.bodySmall?.copyWith(fontFeatures: tab)),
          ]),
        ],
      ),
    );
  }
}
