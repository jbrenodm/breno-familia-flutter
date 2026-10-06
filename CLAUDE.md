# CLAUDE.md — breno-familia-flutter

Instruções para agentes de IA (Claude Code) neste repositório. Leia tudo antes de alterar código.

## O projeto

App Flutter (**Android e Windows**) de controle financeiro pessoal do Breno e da Jaqueline. Versão 2 do PWA
`jbrenodm/breno-financeiro`. Registra **um valor por item por mês** (sem lançamentos individuais com data: escolha do usuário).

- Dados no **Supabase** (Postgres, região São Paulo). Login por e-mail e senha, **sessão persistente** (refresh token salvo pelo `supabase_flutter`).
- **Offline-first com envio automático.** Não reintroduza "Pendente/Publicar": foi justamente o problema que a v2 resolveu.
- Idioma: **tudo em português do Brasil** (interface, mensagens, comentários, commits, docs). Moeda BRL, `intl` com `pt_BR`.

## Stack e restrições

- Flutter estável (≥ 3.35), Material 3, sem gerenciador de estado externo: `Repositorio` (ChangeNotifier) + `RepoScope` (InheritedNotifier).
- Dependências: `supabase_flutter`, `path_provider`, `uuid`, `file_picker`, `intl`. **Não adicione pacotes sem o usuário pedir**
  (nada de Riverpod/Bloc/fl_chart/drift). Gráficos são `CustomPainter` em `ui/graficos.dart`.
- Plataformas: só Android e Windows. As pastas `android/` e `windows/` foram geradas por `dart run tool/preparar.dart`
  (ajustes: permissão INTERNET no manifest, nome do app, título da janela) e estão versionadas no git. Se mudar um ajuste,
  mude no script e no arquivo versionado.
- Configuração por `--dart-define-from-file=env.json` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`). `env.json` nunca vai para o git.

## Mapa do código

```
lib/main.dart              Supabase.initialize + runApp
lib/config.dart            leitura do env
lib/data/modelo.dart       Grupo, Item, Dados (consultas), CalcAno (cálculos), parseMoney, fix12
lib/data/repositorio.dart  TODA alteração de dados passa aqui: muda local → fila → sincronizar()
lib/data/remoto.dart       interface Remoto + RemotoSupabase (única classe que fala com o Supabase)
lib/data/armazenamento.dart arquivo JSON por usuário (dados_<userId>.json na pasta de suporte do app)
lib/ui/app.dart            MaterialApp, PortaoLogin (sessão), TelaLogin, PortaoLar (carrega repo, timers, ciclo de vida), TelaLar
lib/ui/inicio.dart         navegação (NavigationBar < 840 px ≤ NavigationRail), período, IndicadorSync
lib/ui/mes.dart, resumo.dart, graficos.dart, ajustes.dart   telas
lib/ui/comum.dart          diálogos (confirmar, pedirTexto), CampoValor, LinhaValor, Largura
supabase/migrations/       esquema, triggers, RLS, RPCs (criar_lar, entrar_no_lar), publicação realtime
test/                      calculos_test, sincronizacao_test (RemotoFalso), widget_test
```

## Garantias da sincronização (não quebre)

1. Telas **nunca** chamam o Supabase direto: usam métodos do `Repositorio`.
2. Cada alteração: aplica em `dados` → `_enfileirar(chave, tabela, linha)` → `_mudou()` (salva em disco, notifica, agenda envio).
   Chaves: `g:<id>`, `i:<id>`, `v:<itemId>:<mes>`, `lar`. A fila coalesce pela chave.
3. Envio na ordem grupos → itens → valores → lar. Só sai da fila o que não mudou durante o envio (`seq`).
4. Recebimento: "alterados desde cursor − 2 min", paginado de 1000 em 1000. Linha com chave na fila é ignorada (a local vence até ser enviada).
5. `sincronizar()` é serializado (chamadas simultâneas viram uma repetição).
6. Exclusão é sempre lógica (`excluido = true`). Não use DELETE.
7. `updated_at`/`updated_by` são do servidor (trigger `tocar`). Não envie esses campos.
8. `CampoValor` não é sobrescrito enquanto tem foco (atualizações que chegam no meio da digitação esperam).

Mudou o esquema? Crie `supabase/migrations/000N_descricao.sql` (nunca edite uma migração já aplicada), mantenha o RLS em todas as
tabelas e atualize `RemotoFalso` nos testes. **Explique o plano e peça confirmação** antes de mexer em esquema, RLS ou sincronização.

## Regras de cálculo (iguais à planilha original)

Receitas = itens dos grupos `receita`. **Despesas = todos os grupos de despesa, incluindo investimentos.** Investimentos = grupos
`investimento`. Gasto real = Despesas − Investimentos. Saldo = Receitas − Despesas. "X% da receita" = Receitas × metaPct / 100.
**Média = total ÷ meses com lançamento.** `round2` em todo total.

## Segurança

- A chave publishable/anon vai no app (não é segredo). A proteção é: cadastro público desligado + RLS por lar.
- Nunca coloque no repositório `env.json`, keystores, senhas, service_role key nem dados financeiros reais (backups .json).
- Nunca use a `service_role` key no app.

## Interface

- Mobile-first (teste em 390 px), e layout largo no Windows (≥ 840 px: trilho lateral, colunas). Alvos de toque ≥ 40 px.
- Cores pelas `Cores` (ThemeExtension em `tema.dart`), sempre com versão clara **e** escura.
- Diálogos por `confirmar()` e `pedirTexto()`. Avisos por `avisar()` (SnackBar).

## Comandos

```bash
dart run tool/preparar.dart                     # 1ª vez
flutter pub get
flutter analyze && flutter test                 # rode sempre antes de commitar
flutter run -d windows --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json
```

## Fluxo de trabalho

1. Entenda o pedido; se mexer em esquema, RLS, sincronização ou login, explique o plano e peça confirmação.
2. Mudança mínima, no estilo existente. 3. Atualize/crie testes (`RemotoFalso` para tudo que envolve servidor).
4. `flutter analyze && flutter test`. 5. Atualize README.md e docs/decisoes.md quando for decisão de arquitetura.
6. Commits em português, no imperativo, curtos. Não faça push nem crie PR sem o usuário pedir.

## Validação

Já validado (out/2026, Flutter 3.47, supabase_flutter 2.18): `flutter analyze` e `flutter test` limpos; app rodando no
Windows e no Android (Galaxy A55, Android 16); `0001_inicial.sql` aplicado num projeto Supabase real; login e conexão
funcionando.

Ainda falta testar: login persistente (fechar/reabrir, reiniciar o celular), offline (modo avião → lançar → voltar) e
tempo real entre dois aparelhos.
