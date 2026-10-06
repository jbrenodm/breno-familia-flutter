import 'package:flutter/material.dart';

import '../data/modelo.dart';
import '../data/repositorio.dart';
import 'ajustes.dart';
import 'app.dart';
import 'comum.dart';
import 'formato.dart';
import 'graficos.dart';
import 'mes.dart';
import 'resumo.dart';

enum Aba { graficos, mes, resumo, ajustes }

/// Estrutura principal: navegação (barra inferior no celular, trilho lateral no Windows) e seletor de período.
class TelaInicio extends StatefulWidget {
  const TelaInicio({super.key, required this.email});
  final String email;
  @override
  State<TelaInicio> createState() => _TelaInicioState();
}

class _TelaInicioState extends State<TelaInicio> {
  Aba _aba = Aba.mes;
  int _ano = DateTime.now().year;
  int _mes = DateTime.now().month - 1;

  static const _destinos = [
    (Aba.graficos, Icons.bar_chart_outlined, Icons.bar_chart, 'Gráficos'),
    (Aba.mes, Icons.calendar_month_outlined, Icons.calendar_month, 'Mês'),
    (Aba.resumo, Icons.table_chart_outlined, Icons.table_chart, 'Resumo'),
    (Aba.ajustes, Icons.settings_outlined, Icons.settings, 'Ajustes'),
  ];

  /// Garante que o ano exibido existe (outra pessoa pode ter excluído).
  int _anoValido(Repositorio repo) {
    final anos = repo.dados.anos;
    if (anos.isEmpty || anos.contains(_ano)) return _ano;
    return anos.contains(DateTime.now().year) ? DateTime.now().year : anos.last;
  }

  Future<void> _passo(int dir) async {
    final repo = RepoScope.ler(context);
    var a = _anoValido(repo), m = _mes;
    if (_aba == Aba.mes) {
      m += dir;
      if (m < 0) {
        m = 11;
        a--;
      } else if (m > 11) {
        m = 0;
        a++;
      }
    } else {
      a += dir;
    }
    if (!repo.dados.anos.contains(a)) {
      if (dir < 0) return;
      final base = _anoValido(repo);
      final ok = await confirmar(context, 'Criar o ano $a?',
          'Os grupos, itens e fontes de receita de $base serão copiados com valores zerados.',
          ok: 'Criar $a');
      if (!ok || !mounted) return;
      repo.criarAno(a, base: base);
    }
    setState(() {
      _ano = a;
      _mes = m;
    });
  }

  void _definirAno(int a) => setState(() => _ano = a);

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final ano = _anoValido(repo);
    final largo = MediaQuery.sizeOf(context).width >= 840;
    final anos = repo.dados.anos;
    final primeiro = anos.isEmpty ? ano : anos.first;

    final Widget corpo = anos.isEmpty
        ? Center(
            child: FilledButton(onPressed: () => repo.criarAno(DateTime.now().year), child: const Text('Criar o ano atual')),
          )
        : switch (_aba) {
            Aba.graficos => TelaGraficos(ano: ano, largo: largo),
            Aba.mes => TelaMes(key: ValueKey('mes-$ano-$_mes'), ano: ano, mes: _mes),
            Aba.resumo => TelaResumo(ano: ano),
            Aba.ajustes => TelaAjustes(ano: ano, email: widget.email, aoMudarAno: _definirAno),
          };

    final periodo = _aba == Aba.ajustes || anos.isEmpty
        ? const Text('Ajustes')
        : Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: _aba == Aba.mes ? 'Mês anterior' : 'Ano anterior',
              onPressed: (_aba == Aba.mes ? (ano == primeiro && _mes == 0) : ano == primeiro) ? null : () => _passo(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(_aba == Aba.mes ? '${capitalizar(meses[_mes])} de $ano' : '$ano'),
            IconButton(
              tooltip: _aba == Aba.mes ? 'Próximo mês' : 'Próximo ano',
              onPressed: () => _passo(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ]);

    final appBar = AppBar(
      title: periodo,
      centerTitle: !largo,
      actions: const [IndicadorSync(), SizedBox(width: 8)],
    );

    void ir(int i) => setState(() => _aba = _destinos[i].$1);
    final selecionado = _destinos.indexWhere((d) => d.$1 == _aba);

    if (largo) {
      return Scaffold(
        appBar: appBar,
        body: Row(children: [
          NavigationRail(
            selectedIndex: selecionado,
            onDestinationSelected: ir,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in _destinos)
                NavigationRailDestination(icon: Icon(d.$2), selectedIcon: Icon(d.$3), label: Text(d.$4)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: corpo),
        ]),
      );
    }
    return Scaffold(
      appBar: appBar,
      body: corpo,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selecionado,
        onDestinationSelected: ir,
        destinations: [
          for (final d in _destinos) NavigationDestination(icon: Icon(d.$2), selectedIcon: Icon(d.$3), label: d.$4),
        ],
      ),
    );
  }
}

/// Estado da sincronização no topo. Não há ação obrigatória: o envio é automático.
class IndicadorSync extends StatelessWidget {
  const IndicadorSync({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final n = repo.pendentes;
    final (IconData icone, Color? cor, String texto) = switch (repo.estado) {
      EstadoSync.sincronizando => (Icons.cloud_sync_outlined, null, 'Sincronizando…'),
      EstadoSync.sincronizado when n == 0 => (Icons.cloud_done_outlined, null, 'Sincronizado'),
      EstadoSync.sincronizado => (Icons.cloud_upload_outlined, null, 'Enviando…'),
      EstadoSync.offline => (Icons.cloud_off_outlined, cs.onSurfaceVariant, n > 0 ? 'Offline · $n a enviar' : 'Offline'),
      EstadoSync.erro => (Icons.error_outline, cs.error, 'Erro ao sincronizar'),
    };
    return Tooltip(
      message: texto,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _detalhes(context, repo),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icone, size: 20, color: cor),
            if (repo.estado == EstadoSync.offline && n > 0) ...[
              const SizedBox(width: 4),
              Text('$n', style: Theme.of(context).textTheme.labelMedium),
            ],
          ]),
        ),
      ),
    );
  }

  void _detalhes(BuildContext context, Repositorio repo) {
    final u = repo.ultimaSync;
    final hora = u == null ? 'ainda não' : '${u.hour.toString().padLeft(2, '0')}:${u.minute.toString().padLeft(2, '0')}';
    final n = repo.pendentes;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(switch (repo.estado) {
              EstadoSync.offline => 'Sem conexão',
              EstadoSync.erro => 'Erro ao sincronizar',
              EstadoSync.sincronizando => 'Sincronizando',
              EstadoSync.sincronizado => 'Sincronizado',
            }, style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(n == 0
                ? 'Todas as alterações deste aparelho já estão no servidor.'
                : '$n ${n == 1 ? 'alteração guardada' : 'alterações guardadas'} neste aparelho. '
                    'Serão enviadas sozinhas assim que houver conexão.'),
            if (repo.mensagem != null) ...[const SizedBox(height: 8), Text(repo.mensagem!)],
            const SizedBox(height: 8),
            Text('Última sincronização: $hora', style: Theme.of(c).textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () {
                Navigator.pop(c);
                repo.sincronizar();
              },
              child: const Text('Sincronizar agora'),
            ),
          ]),
        ),
      ),
    );
  }
}
