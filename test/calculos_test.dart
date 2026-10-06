import 'package:breno_financeiro/data/modelo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMoney', () {
    test('formatos brasileiros e contas', () {
      expect(parseMoney('1.234,56'), 1234.56);
      expect(parseMoney('1234.56'), 1234.56);
      expect(parseMoney(r'R$ 10'), 10);
      expect(parseMoney('120+35,90'), 155.9);
      expect(parseMoney('100+50,5-20'), 130.5);
      expect(parseMoney('1.000'), 1000);
      expect(parseMoney(''), 0);
      expect(parseMoney('abc'), isNull);
    });
  });

  group('CalcAno', () {
    Dados exemplo() {
      final d = Dados(metaPct: 30);
      d.grupos['r'] = const Grupo(id: 'r', ano: 2026, nome: 'Receitas', tipo: TipoGrupo.receita, ordem: 0);
      d.grupos['c'] = const Grupo(id: 'c', ano: 2026, nome: 'Casa', tipo: TipoGrupo.despesa, ordem: 1);
      d.grupos['i'] = const Grupo(id: 'i', ano: 2026, nome: 'Reserva', tipo: TipoGrupo.investimento, ordem: 2);
      d.grupos['x'] = const Grupo(id: 'x', ano: 2026, nome: 'Excluído', tipo: TipoGrupo.despesa, ordem: 3, excluido: true);
      d.itens['sal'] = const Item(id: 'sal', grupoId: 'r', nome: 'Salário', ordem: 1);
      d.itens['alu'] = const Item(id: 'alu', grupoId: 'c', nome: 'Aluguel', ordem: 1);
      d.itens['cx'] = const Item(id: 'cx', grupoId: 'i', nome: 'Caixinha', ordem: 1);
      d.itens['zz'] = const Item(id: 'zz', grupoId: 'x', nome: 'Velho', ordem: 1);
      d.valores['sal'] = zeros()..[0] = 5000..[1] = 5000;
      d.valores['alu'] = zeros()..[0] = 1500..[1] = 1500;
      d.valores['cx'] = zeros()..[0] = 1000;
      d.valores['zz'] = zeros()..[0] = 999;
      return d;
    }

    test('regras da planilha: despesas incluem investimentos', () {
      final c = CalcAno.de(exemplo(), 2026);
      expect(c.receitas[0], 5000);
      expect(c.despesas[0], 2500);
      expect(c.invest[0], 1000);
      expect(c.gastoReal[0], 1500);
      expect(c.saldo[0], 2500);
      expect(c.meta[0], 1500);
      expect(c.recMenosInv[0], 4000);
    });

    test('grupos excluídos não contam', () {
      final c = CalcAno.de(exemplo(), 2026);
      expect(c.grupos.length, 2);
    });

    test('média = total ÷ meses com lançamento', () {
      final c = CalcAno.de(exemplo(), 2026);
      expect(c.mesesComLancamento, 2);
      expect(c.media(c.receitas), 5000);
      expect(c.media(c.despesas), 2000);
    });
  });
}
