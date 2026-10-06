import 'package:breno_familia_flutter/data/armazenamento.dart';
import 'package:breno_familia_flutter/data/modelo.dart';
import 'package:breno_familia_flutter/data/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_remoto.dart';

void main() {
  late RemotoFalso servidor;
  var n = 0;

  Repositorio novoRepo({Armazenamento? arm, String usuario = 'u1'}) {
    servidor.usuario = usuario;
    return Repositorio(
      remoto: servidor,
      armazenamento: arm ?? ArmazenamentoMemoria(),
      atrasoEnvio: const Duration(hours: 1), // nos testes a sincronização é chamada à mão
      novoId: () => 'id-${++n}',
    );
  }

  setUp(() {
    servidor = RemotoFalso();
    n = 0;
  });

  test('criar o lar cria a estrutura padrão no servidor', () async {
    final a = novoRepo();
    await a.criarLar('Casa');
    expect(a.temLar, isTrue);
    expect(a.pendentes, 0);
    expect(a.estado, EstadoSync.sincronizado);
    final ano = DateTime.now().year;
    expect(a.dados.grupoReceita(ano)?.nome, 'Receitas');
    expect(servidor.tabelas['grupos']!.length, a.dados.grupos.length);
    expect(servidor.tabelas['itens']!.length, a.dados.itens.length);
    a.dispose();
  });

  test('segunda pessoa entra com código e recebe os dados', () async {
    final a = novoRepo();
    await a.criarLar('Casa');
    final ano = DateTime.now().year;
    final item = a.dados.receitasDo(ano).first;
    a.definirValor(item.id, 3, 1234.5);
    await a.sincronizar();

    final b = novoRepo(usuario: 'u2');
    await b.entrarNoLar('abc12345');
    expect(b.larId, a.larId);
    expect(b.dados.valor(item.id, 3), 1234.5);
    expect(b.dados.gruposDoAno(ano).length, a.dados.gruposDoAno(ano).length);
    a.dispose();
    b.dispose();
  });

  test('offline: alterações ficam na fila, sobrevivem ao reinício e são enviadas sozinhas depois', () async {
    final arm = ArmazenamentoMemoria();
    final a = novoRepo(arm: arm);
    await a.criarLar('Casa');
    final ano = DateTime.now().year;
    final item = a.dados.gruposDespesa(ano).first;
    final it = a.dados.itensDo(item.id).first;

    servidor.offline = true;
    a.definirValor(it.id, 0, 99.9);
    await a.sincronizar();
    expect(a.estado, EstadoSync.offline);
    expect(a.pendentes, 1);
    expect(a.estaPendente(it.id, 0), isTrue);
    await a.salvar();
    a.dispose();

    // "Fecha e abre o app" ainda offline: os dados e a fila continuam no aparelho.
    final a2 = novoRepo(arm: arm);
    await a2.carregar();
    expect(a2.dados.valor(it.id, 0), 99.9);
    expect(a2.pendentes, 1);

    servidor.offline = false;
    await a2.sincronizar();
    expect(a2.pendentes, 0);
    expect(a2.estado, EstadoSync.sincronizado);
    expect(servidor.tabelas['valores']!['${it.id}:0']!['valor'], 99.9);
    a2.dispose();
  });

  test('duas pessoas lançando itens diferentes ao mesmo tempo não se sobrescrevem', () async {
    final a = novoRepo();
    await a.criarLar('Casa');
    final b = novoRepo(usuario: 'u2');
    await b.entrarNoLar('ABC12345');
    final ano = DateTime.now().year;
    final itens = a.dados.itensDo(a.dados.gruposDespesa(ano).first.id);

    a.definirValor(itens[0].id, 5, 10);
    b.definirValor(itens[1].id, 5, 20);
    await a.sincronizar();
    await b.sincronizar();
    await a.sincronizar();

    for (final r in [a, b]) {
      expect(r.dados.valor(itens[0].id, 5), 10);
      expect(r.dados.valor(itens[1].id, 5), 20);
    }
    a.dispose();
    b.dispose();
  });

  test('valor ainda não enviado não é sobrescrito pelo que vem do servidor', () async {
    final a = novoRepo();
    await a.criarLar('Casa');
    final b = novoRepo(usuario: 'u2');
    await b.entrarNoLar('ABC12345');
    final ano = DateTime.now().year;
    final it = a.dados.receitasDo(ano).first;

    b.definirValor(it.id, 1, 500);
    await b.sincronizar();

    servidor.offline = true;
    a.definirValor(it.id, 1, 700); // a está offline: fica na fila
    await a.sincronizar();
    servidor.offline = false;
    // Ao voltar, a envia a sua (última gravação vence) e não regride para 500.
    await a.sincronizar();
    expect(a.dados.valor(it.id, 1), 700);
    await b.sincronizar();
    expect(b.dados.valor(it.id, 1), 700);
    a.dispose();
    b.dispose();
  });

  test('estrutura: criar, renomear, mover e excluir chegam à outra pessoa', () async {
    final a = novoRepo();
    await a.criarLar('Casa');
    final b = novoRepo(usuario: 'u2');
    await b.entrarNoLar('ABC12345');
    final ano = DateTime.now().year;

    final g = a.criarGrupo(ano, 'Saúde');
    a.criarItem(g, 'Farmácia');
    a.renomearGrupo(g, 'Saúde e farmácia');
    a.moverGrupo(g, -1);
    final primeiro = a.dados.gruposDespesa(ano).first.id;
    a.excluirGrupo(primeiro);
    await a.sincronizar();
    await b.sincronizar();

    final nomesA = a.dados.gruposDespesa(ano).map((g) => g.nome).toList();
    final nomesB = b.dados.gruposDespesa(ano).map((g) => g.nome).toList();
    expect(nomesB, nomesA);
    expect(nomesB, contains('Saúde e farmácia'));
    expect(b.dados.grupos[primeiro]!.excluido, isTrue);
    a.dispose();
    b.dispose();
  });

  test('novo ano copia a estrutura com valores zerados', () async {
    final a = novoRepo();
    await a.criarLar('Casa');
    final ano = DateTime.now().year;
    final it = a.dados.receitasDo(ano).first;
    a.definirValor(it.id, 0, 100);
    a.criarAno(ano + 1, base: ano);
    expect(a.dados.anos, [ano, ano + 1]);
    expect(a.dados.gruposDoAno(ano + 1).length, a.dados.gruposDoAno(ano).length);
    final novo = a.dados.receitasDo(ano + 1).first;
    expect(novo.id, isNot(it.id));
    expect(a.dados.valor(novo.id, 0), 0);
    a.dispose();
  });

  test('copiar mês anterior preenche só itens zerados', () async {
    final a = novoRepo();
    await a.criarLar('Casa');
    final ano = DateTime.now().year;
    final its = a.dados.receitasDo(ano);
    a.definirValor(its[0].id, 4, 100);
    a.definirValor(its[1].id, 4, 200);
    a.definirValor(its[1].id, 5, 250);
    expect(a.copiarMesAnterior(ano, 5), 1);
    expect(a.dados.valor(its[0].id, 5), 100);
    expect(a.dados.valor(its[1].id, 5), 250);
    a.dispose();
  });

  test('importa o backup do PWA antigo e exporta no mesmo formato', () async {
    final a = novoRepo();
    await a.criarLar('Casa');
    final backup = {
      'app': 'controle-financeiro',
      'version': 1,
      'metaPct': 25,
      'years': {
        '2026': {
          'receitaGroup': {'id': 'abc', 'nome': 'Receitas'},
          'receitas': [
            {'id': 'r1', 'nome': 'Breno', 'valores': [1000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]},
          ],
          'grupos': [
            {
              'id': 'g1',
              'nome': 'Casa',
              'investimento': false,
              'itens': [
                {'id': 'i1', 'nome': 'Aluguel', 'valores': [300, 300, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]},
              ],
            },
            {'id': 'g2', 'nome': 'Reserva', 'investimento': true, 'itens': []},
          ],
        },
      },
    };
    a.importarBackup(backup);
    await a.sincronizar();
    expect(a.dados.anos, [2026]);
    expect(a.dados.metaPct, 25);
    final c = CalcAno.de(a.dados, 2026);
    expect(c.receitas[0], 1000);
    expect(c.despesas[1], 300);
    expect(a.dados.gruposDespesa(2026).last.investimento, isTrue);
    expect(servidor.lares[a.larId]!['meta_pct'], 25);

    final exp = a.exportarBackup();
    final y = (exp['years'] as Map)['2026'] as Map;
    expect((y['receitas'] as List).first['nome'], 'Breno');
    expect(((y['grupos'] as List).first['itens'] as List).first['valores'][1], 300);
    a.dispose();
  });

  test('erros de rede são reconhecidos como offline', () {
    expect(pareceOffline(Exception('SocketException: Failed host lookup')), isTrue);
    expect(pareceOffline(Exception('ClientException: Connection closed')), isTrue);
    expect(pareceOffline(Exception('new row violates row-level security policy')), isFalse);
  });
}
