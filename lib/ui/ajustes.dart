import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/modelo.dart';
import '../data/repositorio.dart';
import 'app.dart';
import 'comum.dart';
import 'formato.dart';

/// Estrutura (anos, receitas, grupos, itens), cálculos, convite, conta, backup e aparência.
class TelaAjustes extends StatelessWidget {
  const TelaAjustes({super.key, required this.ano, required this.email, required this.aoMudarAno});
  final int ano;
  final String email;
  final ValueChanged<int> aoMudarAno;

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final d = repo.dados;
    final anos = d.anos;
    final prefs = PreferenciasScope.of(context);

    return Largura(
      max: 820,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
        const TituloSecao('Ano em edição'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<int>(
                key: ValueKey('ano-$ano-${anos.length}'),
                initialValue: anos.contains(ano) ? ano : null,
                decoration: const InputDecoration(labelText: 'A estrutura (grupos e itens) é guardada por ano'),
                items: [for (final a in anos) DropdownMenuItem(value: a, child: Text('$a'))],
                onChanged: (a) {
                  if (a != null) aoMudarAno(a);
                },
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Novo ano (copia a estrutura)'),
                  onPressed: () async {
                    final s = await pedirTexto(context, 'Novo ano', rotulo: 'Ano', valor: '${(anos.isEmpty ? ano : anos.last) + 1}', teclado: TextInputType.number);
                    if (s == null || !context.mounted) return;
                    final a = int.tryParse(s);
                    if (a == null || a < 2000 || a > 2100) {
                      avisar(context, 'Ano inválido');
                      return;
                    }
                    if (anos.contains(a)) {
                      avisar(context, 'Esse ano já existe');
                      return;
                    }
                    repo.criarAno(a, base: ano);
                    aoMudarAno(a);
                    avisar(context, 'Ano $a criado');
                  },
                ),
                if (anos.length > 1)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    label: Text('Excluir $ano'),
                    onPressed: () async {
                      if (!await confirmar(context, 'Excluir $ano?', 'Todos os valores e a estrutura deste ano serão apagados.',
                          ok: 'Excluir', perigo: true)) {
                        return;
                      }
                      repo.excluirAno(ano);
                      aoMudarAno(repo.dados.anos.last);
                    },
                  ),
              ]),
            ]),
          ),
        ),

        const TituloSecao('Receitas (fontes)'),
        Card(
          child: Column(children: [
            for (final (k, i) in d.receitasDo(ano).indexed)
              _LinhaItem(item: i, primeiro: k == 0, ultimo: k == d.receitasDo(ano).length - 1),
            _BotaoAdicionar('Fonte de receita', () async {
              final n = await pedirTexto(context, 'Nova fonte de receita');
              if (n != null) repo.criarReceita(ano, n);
            }),
          ]),
        ),

        const TituloSecao('Grupos de despesa'),
        for (final (k, g) in d.gruposDespesa(ano).indexed) _CartaoGrupoAjuste(grupo: g, primeiro: k == 0, ultimo: k == d.gruposDespesa(ano).length - 1),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Novo grupo'),
          onPressed: () async {
            final n = await pedirTexto(context, 'Novo grupo');
            if (n != null) repo.criarGrupo(ano, n);
          },
        ),

        const TituloSecao('Cálculos'),
        Card(
          child: ListTile(
            title: const Text('Percentual da receita exibido no resumo'),
            subtitle: const Text('Na planilha original: 30%'),
            trailing: Text('${pct(d.metaPct)}%', style: Theme.of(context).textTheme.titleMedium),
            onTap: () async {
              final s = await pedirTexto(context, 'Percentual da receita', rotulo: '%', valor: pct(d.metaPct), teclado: TextInputType.number);
              if (s == null || !context.mounted) return;
              final p = parseMoney(s);
              if (p == null || p < 0 || p > 100) {
                avisar(context, 'Informe um percentual entre 0 e 100');
                return;
              }
              repo.definirMeta(p);
            },
          ),
        ),

        const TituloSecao('Compartilhamento'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: Text('Código de convite: ${repo.larCodigo ?? '…'}'),
              subtitle: const Text('Quem entrar no app com a própria conta e digitar este código passa a ver e editar os mesmos dados.'),
              trailing: IconButton(
                tooltip: 'Copiar código',
                icon: const Icon(Icons.copy),
                onPressed: repo.larCodigo == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: repo.larCodigo!));
                        avisar(context, 'Código copiado');
                      },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(email),
              subtitle: const Text('Sessão salva neste aparelho'),
              trailing: TextButton(onPressed: () => _sair(context, repo), child: const Text('Sair')),
            ),
          ]),
        ),

        const TituloSecao('Backup'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Exportar backup (.json)'),
              subtitle: const Text('Mesmo formato do backup do app antigo'),
              onTap: () => _exportar(context, repo),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.upload_outlined),
              title: const Text('Importar backup (.json)'),
              subtitle: const Text('Aceita o backup exportado pelo app antigo (PWA). Substitui todos os dados.'),
              onTap: () => _importar(context, repo),
            ),
          ]),
        ),

        const TituloSecao('Aparência'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Automático')),
                ButtonSegment(value: ThemeMode.light, label: Text('Claro')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Escuro')),
              ],
              selected: {prefs.tema},
              onSelectionChanged: (s) => prefs.tema = s.first,
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _sair(BuildContext context, Repositorio repo) async {
    final n = repo.pendentes;
    final ok = await confirmar(
      context,
      'Sair da conta?',
      n == 0
          ? 'Você precisará do e-mail e da senha para entrar de novo neste aparelho.'
          : 'Há $n ${n == 1 ? 'alteração' : 'alterações'} ainda não enviadas. Elas ficam guardadas neste aparelho e serão enviadas quando você entrar de novo.',
      ok: 'Sair',
    );
    if (!ok) return;
    await repo.salvar();
    repo.parar();
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _exportar(BuildContext context, Repositorio repo) async {
    final nome = 'controle-financeiro-${DateTime.now().toIso8601String().substring(0, 10)}.json';
    final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(repo.exportarBackup())));
    try {
      final caminho = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar backup',
        fileName: nome,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (caminho == null) return;
      // No Windows o seletor só devolve o caminho: o app grava o arquivo.
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) await File(caminho).writeAsBytes(bytes);
      if (context.mounted) avisar(context, 'Backup salvo');
    } catch (e) {
      if (context.mounted) avisar(context, 'Não foi possível salvar: $e');
    }
  }

  Future<void> _importar(BuildContext context, Repositorio repo) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['json'], withData: true);
    final arq = r?.files.single;
    if (arq == null || !context.mounted) return;
    try {
      final bytes = arq.bytes ?? await File(arq.path!).readAsBytes();
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (!context.mounted) return;
      final ok = await confirmar(context, 'Importar backup?', 'Todos os dados (de todos os anos) serão substituídos pelos do arquivo, para todos que usam o app.',
          ok: 'Importar', perigo: true);
      if (!ok) return;
      repo.importarBackup(j);
      if (context.mounted) {
        aoMudarAno(repo.dados.anos.contains(ano) ? ano : repo.dados.anos.last);
        avisar(context, 'Backup importado');
      }
    } catch (e) {
      if (context.mounted) avisar(context, 'Arquivo inválido');
    }
  }
}

class _BotaoAdicionar extends StatelessWidget {
  const _BotaoAdicionar(this.texto, this.aoTocar);
  final String texto;
  final VoidCallback aoTocar;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: TextButton.icon(icon: const Icon(Icons.add), label: Text(texto), onPressed: aoTocar),
        ),
      );
}

enum _Acao { renomear, subir, descer, excluir }

PopupMenuButton<_Acao> _menu({required bool primeiro, required bool ultimo, required ValueChanged<_Acao> aoEscolher}) =>
    PopupMenuButton<_Acao>(
      tooltip: 'Opções',
      onSelected: aoEscolher,
      itemBuilder: (_) => [
        const PopupMenuItem(value: _Acao.renomear, child: Text('Renomear')),
        PopupMenuItem(value: _Acao.subir, enabled: !primeiro, child: const Text('Subir')),
        PopupMenuItem(value: _Acao.descer, enabled: !ultimo, child: const Text('Descer')),
        const PopupMenuItem(value: _Acao.excluir, child: Text('Excluir')),
      ],
    );

class _LinhaItem extends StatelessWidget {
  const _LinhaItem({required this.item, required this.primeiro, required this.ultimo});
  final Item item;
  final bool primeiro, ultimo;

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.ler(context);
    return ListTile(
      dense: true,
      title: Text(item.nome.isEmpty ? '(sem nome)' : item.nome),
      onTap: () => _renomear(context, repo),
      trailing: _menu(
        primeiro: primeiro,
        ultimo: ultimo,
        aoEscolher: (a) async {
          switch (a) {
            case _Acao.renomear:
              _renomear(context, repo);
            case _Acao.subir:
              repo.moverItem(item.id, -1);
            case _Acao.descer:
              repo.moverItem(item.id, 1);
            case _Acao.excluir:
              final total = soma(repo.dados.valoresDo(item.id));
              final ok = await confirmar(context, 'Excluir "${item.nome}"?',
                  'O item será removido deste ano.${total != 0 ? ' Há ${brl(total)} lançados no ano que deixarão de contar.' : ''}',
                  ok: 'Excluir', perigo: true);
              if (ok) repo.excluirItem(item.id);
          }
        },
      ),
    );
  }

  Future<void> _renomear(BuildContext context, Repositorio repo) async {
    final n = await pedirTexto(context, 'Renomear', valor: item.nome);
    if (n != null) repo.renomearItem(item.id, n);
  }
}

class _CartaoGrupoAjuste extends StatelessWidget {
  const _CartaoGrupoAjuste({required this.grupo, required this.primeiro, required this.ultimo});
  final Grupo grupo;
  final bool primeiro, ultimo;

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.ler(context);
    final itens = repo.dados.itensDo(grupo.id);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('cfg-${grupo.id}'),
        shape: const Border(),
        title: Text(grupo.nome),
        subtitle: Text('${itens.length} ${itens.length == 1 ? 'item' : 'itens'}${grupo.investimento ? ' · investimento' : ''}'),
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Grupo'),
            trailing: _menu(
              primeiro: primeiro,
              ultimo: ultimo,
              aoEscolher: (a) async {
                switch (a) {
                  case _Acao.renomear:
                    final n = await pedirTexto(context, 'Renomear grupo', valor: grupo.nome);
                    if (n != null) repo.renomearGrupo(grupo.id, n);
                  case _Acao.subir:
                    repo.moverGrupo(grupo.id, -1);
                  case _Acao.descer:
                    repo.moverGrupo(grupo.id, 1);
                  case _Acao.excluir:
                    final total = soma(itens.expand((i) => repo.dados.valoresDo(i.id)));
                    final ok = await confirmar(context, 'Excluir "${grupo.nome}"?',
                        'O grupo e seus ${itens.length} itens serão removidos de ${grupo.ano}.${total != 0 ? ' Há ${brl(total)} lançados no ano que deixarão de contar.' : ''}',
                        ok: 'Excluir', perigo: true);
                    if (ok) repo.excluirGrupo(grupo.id);
                }
              },
            ),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Conta como investimento/reserva'),
            subtitle: const Text('Sai do "gasto real" e entra em "Receitas − Investimentos"'),
            value: grupo.investimento,
            onChanged: (v) => repo.definirInvestimento(grupo.id, v),
          ),
          const Divider(height: 1),
          for (final (k, i) in itens.indexed) _LinhaItem(item: i, primeiro: k == 0, ultimo: k == itens.length - 1),
          _BotaoAdicionar('Item', () async {
            final n = await pedirTexto(context, 'Novo item em ${grupo.nome}');
            if (n != null) repo.criarItem(grupo.id, n);
          }),
        ],
      ),
    );
  }
}
