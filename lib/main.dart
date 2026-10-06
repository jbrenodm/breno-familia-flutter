import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Config.valida) {
    // A sessão fica salva no aparelho e é renovada sozinha (refresh token): login persistente.
    try {
      await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseAnonKey);
    } catch (e) {
      // Sem internet ao abrir: a sessão salva continua valendo e é renovada quando a conexão voltar.
      debugPrint('Supabase.initialize: $e');
    }
  }
  final prefs = await Preferencias.carregar();
  runApp(App(preferencias: prefs));
}
