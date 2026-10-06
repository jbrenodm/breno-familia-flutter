/// Configuração vinda de `--dart-define-from-file=env.json` (ver env.example.json).
/// A chave "publishable"/anon do Supabase não é segredo: a proteção dos dados vem do login e das regras (RLS).
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get valida => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
