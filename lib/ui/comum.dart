import 'package:flutter/material.dart';

import '../data/modelo.dart';
import 'formato.dart';
import 'tema.dart';

void avisar(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}

Future<bool> confirmar(BuildContext context, String titulo, String texto, {String ok = 'Confirmar', bool perigo = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(
          style: perigo ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

Future<String?> pedirTexto(BuildContext context, String titulo, {String rotulo = 'Nome', String valor = '', TextInputType? teclado}) {
  return showDialog<String>(
    context: context,
    builder: (c) => _DialogoTexto(titulo: titulo, rotulo: rotulo, valor: valor, teclado: teclado),
  );
}

class _DialogoTexto extends StatefulWidget {
  const _DialogoTexto({required this.titulo, required this.rotulo, required this.valor, this.teclado});
  final String titulo, rotulo, valor;
  final TextInputType? teclado;
  @override
  State<_DialogoTexto> createState() => _DialogoTextoState();
}

class _DialogoTextoState extends State<_DialogoTexto> {
  late final _c = TextEditingController(text: widget.valor);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    final v = _c.text.trim();
    Navigator.pop(context, v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.titulo),
        content: TextField(
          controller: _c,
          autofocus: true,
          keyboardType: widget.teclado,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: widget.rotulo),
          onSubmitted: (_) => _ok(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _ok, child: const Text('Salvar')),
        ],
      );
}

/// Campo de valor em reais. Aceita contas ("120+35,90"). Grava ao sair do campo ou ao confirmar.
/// Enquanto tem foco, não é sobrescrito por atualizações vindas da sincronização.
class CampoValor extends StatefulWidget {
  const CampoValor({super.key, required this.valor, required this.aoMudar, this.pendente = false, this.rotulo});
  final double valor;
  final ValueChanged<double> aoMudar;
  final bool pendente;
  final String? rotulo;

  @override
  State<CampoValor> createState() => _CampoValorState();
}

class _CampoValorState extends State<CampoValor> {
  late final _c = TextEditingController(text: num2(widget.valor));
  final _foco = FocusNode();

  @override
  void initState() {
    super.initState();
    _foco.addListener(() {
      if (_foco.hasFocus) {
        _c.text = widget.valor == 0 ? '' : num2(widget.valor);
        _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
      } else {
        _confirmar();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(CampoValor old) {
    super.didUpdateWidget(old);
    if (!_foco.hasFocus && old.valor != widget.valor) _c.text = num2(widget.valor);
  }

  void _confirmar() {
    final v = parseMoney(_c.text);
    if (v == null) {
      if (mounted) {
        avisar(context, 'Valor inválido');
        _c.text = num2(widget.valor);
      }
      return;
    }
    if (mounted) _c.text = num2(v);
    if (v != widget.valor) widget.aoMudar(v);
  }

  @override
  void dispose() {
    _foco.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final zero = widget.valor == 0 && !_foco.hasFocus;
    return SizedBox(
      width: 132,
      child: Semantics(
        label: widget.rotulo,
        child: TextField(
        controller: _c,
        focusNode: _foco,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        style: t.textTheme.bodyMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          color: zero ? t.colorScheme.onSurfaceVariant.withValues(alpha: 0.6) : null,
        ),
        decoration: InputDecoration(
          isDense: true,
          prefixText: r'R$ ',
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          // Marca discreta enquanto o valor ainda não chegou ao servidor (envio é automático).
          enabledBorder: widget.pendente
              ? OutlineInputBorder(borderSide: BorderSide(color: Cores.of(context).pendente))
              : null,
        ),
      ),
      ),
    );
  }
}

/// Totais em linha: rótulo à esquerda, valor à direita.
class LinhaValor extends StatelessWidget {
  const LinhaValor(this.rotulo, this.valor, {super.key, this.cor, this.forte = false, this.ponto});
  final String rotulo;
  final double valor;
  final Color? cor, ponto;
  final bool forte;

  @override
  Widget build(BuildContext context) {
    final st = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: forte ? FontWeight.w600 : null,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        if (ponto != null) ...[
          Container(width: 10, height: 10, decoration: BoxDecoration(color: ponto, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
        ],
        Expanded(child: Text(rotulo, style: st)),
        Text(brl(valor), style: st?.copyWith(color: cor)),
      ]),
    );
  }
}

Color? corSaldo(BuildContext context, double v) => v > 0
    ? Cores.of(context).pos
    : v < 0
        ? Cores.of(context).neg
        : null;

class TituloSecao extends StatelessWidget {
  const TituloSecao(this.texto, {super.key});
  final String texto;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(texto.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  letterSpacing: 0.8,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
      );
}

/// Limita a largura do conteúdo em telas grandes (Windows).
class Largura extends StatelessWidget {
  const Largura({super.key, required this.child, this.max = 1100});
  final Widget child;
  final double max;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child),
      );
}
