import 'package:flutter/material.dart';

/// Cores das séries (iguais às do PWA): receitas azul, gasto real laranja, investimentos verde-água.
class Cores extends ThemeExtension<Cores> {
  const Cores({required this.receita, required this.despesa, required this.invest, required this.pos, required this.neg, required this.pendente});

  final Color receita, despesa, invest, pos, neg, pendente;

  static const claro = Cores(
    receita: Color(0xFF2A78D6),
    despesa: Color(0xFFEB6834),
    invest: Color(0xFF1BAF7A),
    pos: Color(0xFF0F7A3D),
    neg: Color(0xFFC62F2E),
    pendente: Color(0xFFB7791F),
  );
  static const escuro = Cores(
    receita: Color(0xFF5B9CEB),
    despesa: Color(0xFFF08A5D),
    invest: Color(0xFF3CC795),
    pos: Color(0xFF4CC27E),
    neg: Color(0xFFF26B6A),
    pendente: Color(0xFFE0A54A),
  );

  static Cores of(BuildContext context) => Theme.of(context).extension<Cores>() ?? claro;

  @override
  Cores copyWith({Color? receita, Color? despesa, Color? invest, Color? pos, Color? neg, Color? pendente}) => Cores(
        receita: receita ?? this.receita,
        despesa: despesa ?? this.despesa,
        invest: invest ?? this.invest,
        pos: pos ?? this.pos,
        neg: neg ?? this.neg,
        pendente: pendente ?? this.pendente,
      );

  @override
  Cores lerp(ThemeExtension<Cores>? other, double t) {
    if (other is! Cores) return this;
    return Cores(
      receita: Color.lerp(receita, other.receita, t)!,
      despesa: Color.lerp(despesa, other.despesa, t)!,
      invest: Color.lerp(invest, other.invest, t)!,
      pos: Color.lerp(pos, other.pos, t)!,
      neg: Color.lerp(neg, other.neg, t)!,
      pendente: Color.lerp(pendente, other.pendente, t)!,
    );
  }
}

ThemeData criarTema(Brightness b) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1C5CAB), brightness: b),
    extensions: [b == Brightness.dark ? Cores.escuro : Cores.claro],
  );
  return base.copyWith(
    inputDecorationTheme: const InputDecorationTheme(isDense: true, border: OutlineInputBorder()),
    cardTheme: base.cardTheme.copyWith(margin: const EdgeInsets.symmetric(vertical: 4)),
  );
}
