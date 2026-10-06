# breno-financeiro-app — Controle Financeiro Pessoal (Flutter)

Versão 2 do [breno-financeiro](https://github.com/jbrenodm/breno-financeiro), agora como app **Android e Windows**,
com os dados no **Supabase** (Postgres na nuvem, região São Paulo).

O que muda em relação ao PWA:

| PWA (v1) | App Flutter (v2) |
|---|---|
| Login Google com token de ~1 h, sem renovação no Android | **Login uma vez por aparelho** (e-mail e senha). A sessão fica salva e se renova sozinha |
| Valores "Pendente" até tocar em **Publicar** | **Envio automático**: tudo vale na hora no aparelho e sobe sozinho quando há conexão. Sem botão Publicar |
| Google Sheets como banco (formato `cfp-1`) | Postgres (Supabase) com regras de acesso por usuário (RLS) |
| Mudança de estrutura exigia internet | Tudo funciona offline, inclusive criar/renomear/excluir grupos e itens |

As telas são as mesmas: **Gráficos**, **Mês**, **Resumo** e **Ajustes**. No campo de valor dá para digitar contas: `120+35,90`.

## 1. Supabase (uma vez só)

1. Crie uma conta em <https://supabase.com> → **New project**. Região: **South America (São Paulo)**. Guarde a senha do banco.
2. **SQL Editor** → cole e rode o conteúdo de [`supabase/migrations/0001_inicial.sql`](supabase/migrations/0001_inicial.sql).
3. **Authentication → Sign In / Providers → Email**: deixe o e-mail ligado e **desligue "Allow new users to sign up"**.
   Assim só entram as contas que você criar.
4. **Authentication → Users → Add user → Create new user**: crie a sua conta e a da Jaqueline
   (marque *Auto Confirm User*).
5. **Project Settings → API**: copie a **Project URL** e a chave **publishable** (ou *anon public*).
   Essa chave não é segredo: a proteção vem do login e das regras RLS do passo 2.

> Plano gratuito: o projeto é pausado depois de 7 dias sem **nenhum** acesso (reativa-se no painel com um clique).
> Ele não tem backup para download; use **Ajustes → Exportar backup** de vez em quando.

## 2. Rodar no computador

Requisitos: [Flutter](https://docs.flutter.dev/get-started/install/windows) estável (3.35 ou mais novo),
Android Studio (para o SDK Android) e, para o app Windows, Visual Studio com *Desktop development with C++*.

```powershell
copy env.example.json env.json      # e preencha URL e chave do passo 1.5 (env.json não vai para o git)
dart run tool/preparar.dart         # 1ª vez: gera as pastas android/ e windows/ e aplica os ajustes
flutter pub get
flutter run -d windows --dart-define-from-file=env.json
flutter run -d <celular>  --dart-define-from-file=env.json   # celular com depuração USB
```

Gerar os instaladores:

```powershell
flutter build apk --release --dart-define-from-file=env.json      # build\app\outputs\flutter-apk\app-release.apk
flutter build windows --release --dart-define-from-file=env.json  # build\windows\x64\runner\Release\
```

Instale o APK no celular (permitir "fontes desconhecidas"). Para atualizar, instale o APK novo por cima: os dados e o login continuam.
Use sempre o **mesmo computador** (ou a mesma chave, ver CI) para gerar o APK: o Android só aceita a atualização assinada com a mesma chave.

## 3. Primeiro acesso

1. **Você:** entre com e-mail e senha → **Criar os dados da casa** (vem com os grupos e itens da planilha).
2. Migrar do app antigo: no PWA, **Ajustes → Exportar backup (.json)**. No app novo, **Ajustes → Importar backup**.
3. **Jaqueline:** entra com a conta dela → digita o **código de convite** que aparece em *Ajustes → Compartilhamento* no seu app.

## Como a sincronização funciona

- Toda alteração vale na hora no aparelho e entra numa fila salva em disco. O app envia sozinho em menos de 1 s quando há internet.
- O ícone de nuvem no topo mostra o estado: sincronizado, sincronizando, **offline** (com o número de alterações guardadas) ou erro.
  Tocar nele mostra os detalhes e um "Sincronizar agora", mas nunca é obrigatório.
- Valores são gravados **por célula** (item × mês): os dois podem lançar ao mesmo tempo sem um apagar o do outro.
  Se os dois mudarem a mesma célula, vale a última que chegou ao servidor.
- As mudanças da outra pessoa chegam em tempo real (Supabase Realtime), ao voltar para o app e a cada minuto.
- Nada é apagado de verdade: excluir marca o registro como excluído, para a exclusão chegar a todos os aparelhos.

## CI (GitHub Actions)

A cada push na `main`: `flutter analyze`, `flutter test`, e os builds Android (APK) e Windows ficam como *artifacts* do workflow.
Configure em **Settings → Secrets and variables → Actions**:

- Variáveis: `SUPABASE_URL` e `SUPABASE_ANON_KEY`.
- Segredo opcional `ANDROID_DEBUG_KEYSTORE_BASE64`: o seu `%USERPROFILE%\.android\debug.keystore` em base64
  (`[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.android\debug.keystore"))`).
  Com ele, o APK do CI tem a mesma assinatura do APK gerado no seu PC e pode ser instalado por cima.

## Estrutura

```
lib/
  main.dart               inicializa o Supabase (sessão persistente) e o app
  config.dart             URL/chave vindas de env.json (--dart-define-from-file)
  data/modelo.dart        Grupo, Item, Dados, CalcAno (regras de cálculo), parseMoney
  data/repositorio.dart   fonte única de dados: alterações locais, fila, sincronização, backup
  data/remoto.dart        Supabase (upsert, "alterados desde", RPCs, tempo real)
  data/armazenamento.dart arquivo JSON no aparelho
  ui/                     telas: app (login/lar), inicio, mes, resumo, graficos, ajustes
supabase/migrations/      esquema do banco + regras de acesso (RLS)
test/                     cálculos, sincronização (servidor falso) e campo de valor
tool/preparar.dart        gera android/ e windows/ e aplica os ajustes
```

## Licença

[MIT](LICENSE) © 2026 Breno
