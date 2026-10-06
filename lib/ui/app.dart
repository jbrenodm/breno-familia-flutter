import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/armazenamento.dart';
import '../data/remoto.dart';
import '../data/repositorio.dart';
import 'inicio.dart';
import 'tema.dart';

/* ---------------- preferências do aparelho (tema) ---------------- */

class Preferencias extends ChangeNotifier {
  Preferencias._(this._arquivo, this._tema);
  final File? _arquivo;
  ThemeMode _tema;

  ThemeMode get tema => _tema;
  set tema(ThemeMode t) {
    _tema = t;
    notifyListeners();
    _gravar();
  }

  Future<void> _gravar() async {
    try {
      await _arquivo?.writeAsString(jsonEncode({'tema': _tema.name}));
    } catch (_) {}
  }

  static Future<Preferencias> carregar() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}preferencias.json');
      var tema = ThemeMode.system;
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        tema = ThemeMode.values.firstWhere((t) => t.name == j['tema'], orElse: () => ThemeMode.system);
      }
      return Preferencias._(f, tema);
    } catch (_) {
      return Preferencias._(null, ThemeMode.system);
    }
  }
}

class PreferenciasScope extends InheritedNotifier<Preferencias> {
  const PreferenciasScope({super.key, required Preferencias super.notifier, required super.child});
  static Preferencias of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<PreferenciasScope>()!.notifier!;
}

/// Dá acesso ao [Repositorio] para as telas (e as reconstrói quando os dados mudam).
class RepoScope extends InheritedNotifier<Repositorio> {
  const RepoScope({super.key, required Repositorio super.notifier, required super.child});
  static Repositorio of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<RepoScope>()!.notifier!;
  static Repositorio ler(BuildContext c) => c.getInheritedWidgetOfExactType<RepoScope>()!.notifier!;
}

/* ---------------- app ---------------- */

class App extends StatelessWidget {
  const App({super.key, required this.preferencias});
  final Preferencias preferencias;

  @override
  Widget build(BuildContext context) {
    return PreferenciasScope(
      notifier: preferencias,
      child: ListenableBuilder(
        listenable: preferencias,
        builder: (context, _) => MaterialApp(
          title: 'Controle Financeiro',
          debugShowCheckedModeBanner: false,
          theme: criarTema(Brightness.light),
          darkTheme: criarTema(Brightness.dark),
          themeMode: preferencias.tema,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Config.valida ? const PortaoLogin() : const _SemConfig(),
        ),
      ),
    );
  }
}

class _SemConfig extends StatelessWidget {
  const _SemConfig();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'App compilado sem a configuração do Supabase.\n\n'
              'Rode com: flutter run --dart-define-from-file=env.json\n(veja env.example.json e o README).',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}

/// Mostra o login ou o app, conforme a sessão salva no aparelho.
class PortaoLogin extends StatelessWidget {
  const PortaoLogin({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final user = auth.currentSession?.user;
        if (user == null) return const TelaLogin();
        return PortaoLar(key: ValueKey(user.id), userId: user.id, email: user.email ?? '');
      },
    );
  }
}

/* ---------------- login ---------------- */

class TelaLogin extends StatefulWidget {
  const TelaLogin({super.key});
  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _ocupado = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: _email.text.trim(), password: _senha.text);
    } on AuthException catch (e) {
      setState(() => _erro = pareceOffline(e)
          ? 'Sem conexão. Para o primeiro acesso é preciso internet.'
          : (e.message.contains('Invalid login') ? 'E-mail ou senha incorretos.' : e.message));
    } catch (e) {
      setState(() => _erro = pareceOffline(e) ? 'Sem conexão. Para o primeiro acesso é preciso internet.' : '$e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.account_balance_wallet_outlined, size: 56, color: t.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Controle Financeiro', textAlign: TextAlign.center, style: t.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('Você só precisa entrar uma vez neste aparelho.', textAlign: TextAlign.center, style: t.textTheme.bodySmall),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _senha,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _ocupado ? null : _entrar(),
                    decoration: const InputDecoration(labelText: 'Senha'),
                  ),
                  if (_erro != null) ...[
                    const SizedBox(height: 12),
                    Text(_erro!, style: TextStyle(color: t.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _ocupado ? null : _entrar,
                    child: _ocupado
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Entrar'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'As contas são criadas pelo Breno no painel do Supabase. Esqueceu a senha? Peça para ele redefinir.',
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------------- lar (dados compartilhados) ---------------- */

/// Carrega os dados deste usuário guardados no aparelho e encontra o lar dele no servidor.
class PortaoLar extends StatefulWidget {
  const PortaoLar({super.key, required this.userId, required this.email});
  final String userId, email;
  @override
  State<PortaoLar> createState() => _PortaoLarState();
}

enum _Fase { carregando, semLar, semConexao, pronto }

class _PortaoLarState extends State<PortaoLar> with WidgetsBindingObserver {
  Repositorio? _repo;
  _Fase _fase = _Fase.carregando;
  Timer? _periodico;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _abrir();
  }

  Future<void> _abrir() async {
    final dir = await getApplicationSupportDirectory();
    final repo = Repositorio(
      remoto: RemotoSupabase(Supabase.instance.client),
      armazenamento: ArmazenamentoArquivo('${dir.path}${Platform.pathSeparator}dados_${widget.userId}.json'),
    );
    await repo.carregar();
    if (!mounted) {
      repo.dispose();
      return;
    }
    _repo = repo;
    await _localizar();
  }

  Future<void> _localizar() async {
    final repo = _repo!;
    setState(() => _fase = _Fase.carregando);
    try {
      final achou = await repo.localizarLar();
      if (!mounted) return;
      if (achou) {
        _comecar();
      } else {
        setState(() => _fase = _Fase.semLar);
      }
    } catch (e) {
      if (!mounted) return;
      // Sem internet: se já há dados no aparelho, abre com eles.
      if (repo.temLar) {
        _comecar();
      } else {
        setState(() => _fase = pareceOffline(e) ? _Fase.semConexao : _Fase.semLar);
      }
    }
  }

  void _comecar() {
    _repo!.iniciar();
    _periodico?.cancel();
    _periodico = Timer.periodic(const Duration(minutes: 1), (_) => _repo?.sincronizar());
    if (mounted) setState(() => _fase = _Fase.pronto);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _fase == _Fase.pronto) _repo?.sincronizar();
    if (state == AppLifecycleState.paused) _repo?.salvar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodico?.cancel();
    _repo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo;
    return switch (_fase) {
      _Fase.carregando => const Scaffold(body: Center(child: CircularProgressIndicator())),
      _Fase.semConexao => _Aviso(
          texto: 'Sem conexão. No primeiro acesso deste aparelho é preciso internet para baixar os dados.',
          acao: 'Tentar de novo',
          aoTocar: _localizar,
        ),
      _Fase.semLar => TelaLar(repo: repo!, email: widget.email, aoConcluir: _comecar),
      _Fase.pronto => RepoScope(notifier: repo!, child: TelaInicio(email: widget.email)),
    };
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, required this.acao, required this.aoTocar});
  final String texto, acao;
  final VoidCallback aoTocar;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(texto, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: aoTocar, child: Text(acao)),
              TextButton(onPressed: () => Supabase.instance.client.auth.signOut(), child: const Text('Sair da conta')),
            ]),
          ),
        ),
      );
}

/// Primeiro acesso: criar o lar (Breno) ou entrar com o código de convite (Jaqueline).
class TelaLar extends StatefulWidget {
  const TelaLar({super.key, required this.repo, required this.email, required this.aoConcluir});
  final Repositorio repo;
  final String email;
  final VoidCallback aoConcluir;
  @override
  State<TelaLar> createState() => _TelaLarState();
}

class _TelaLarState extends State<TelaLar> {
  final _codigo = TextEditingController();
  bool _ocupado = false;
  String? _erro;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _fazer(Future<void> Function() f) async {
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await f();
      widget.aoConcluir();
    } catch (e) {
      final s = '$e';
      setState(() => _erro = pareceOffline(e)
          ? 'Sem conexão.'
          : s.contains('inválido')
              ? 'Código de convite inválido.'
              : s);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Primeiro acesso'), actions: [
        TextButton(onPressed: () => Supabase.instance.client.auth.signOut(), child: const Text('Sair')),
      ]),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Conectado como ${widget.email}', style: t.textTheme.bodySmall),
              const SizedBox(height: 20),
              Text('Já tem um código de convite?', style: t.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _codigo,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Código (em Ajustes, no app de quem já usa)'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _ocupado ? null : () => _fazer(() => widget.repo.entrarNoLar(_codigo.text)),
                child: const Text('Entrar com o código'),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider()),
              Text('Primeira pessoa a usar?', style: t.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Cria os dados da casa com os grupos e itens da planilha. Depois, em Ajustes, você pode importar '
                'o backup .json do app antigo e copiar o código de convite para a Jaqueline.',
                style: t.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _ocupado ? null : () => _fazer(() => widget.repo.criarLar('Nossa casa')),
                child: const Text('Criar os dados da casa'),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(_erro!, style: TextStyle(color: t.colorScheme.error)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
