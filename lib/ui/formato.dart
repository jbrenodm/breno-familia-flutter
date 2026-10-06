import 'package:intl/intl.dart';

final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final _dec = NumberFormat.decimalPatternDigits(locale: 'pt_BR', decimalDigits: 2);

String brl(num v) => _brl.format(v);
String num2(num v) => _dec.format(v);

/// "1,2 mil", "3,4 mi" — eixos dos gráficos.
String curto(num n) {
  final a = n.abs();
  final f = NumberFormat.decimalPatternDigits(locale: 'pt_BR', decimalDigits: 1);
  if (a >= 1e6) return '${f.format(n / 1e6)} mi'.replaceAll(',0 ', ' ');
  if (a >= 1e3) return '${f.format(n / 1e3)} mil'.replaceAll(',0 ', ' ');
  return n.round().toString();
}

/// "30" em vez de "30,00" para percentuais inteiros.
String pct(num v) => v == v.roundToDouble() ? v.round().toString() : num2(v);

String capitalizar(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
