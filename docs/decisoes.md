# Decisões de arquitetura

Registro curto do porquê das escolhas. Acrescente novas no topo, com data.

## 2026-10-05 — Versão 2 em Flutter + Supabase
- **Problemas do PWA (v1):**
  - Sem login persistente: o token do Google Identity Services dura ~1 h, não há refresh token no navegador sem backend,
    e a renovação silenciosa falha no Android. Com o OAuth em modo Teste, a autorização do escopo de planilhas ainda expira a cada 7 dias.
  - O fluxo "Pendente/Publicado" existia só para contornar a falta de sessão: o usuário tinha de lembrar de publicar.
- **Decisão:** app Flutter para **Android e Windows**, com **Supabase** (Postgres em São Paulo) e login por **e-mail e senha**.
  - A sessão do Supabase (access token + refresh token) fica salva no aparelho e se renova sozinha: entra-se uma vez por aparelho.
  - **Offline-first com envio automático:** a alteração vale na hora no aparelho, entra numa fila em disco e é enviada sozinha.
    Não existe "Publicar". O topo só informa o estado (sincronizado/offline/erro).
  - A planilha do Google deixa de ser a fonte de dados. A migração é pelo backup .json do PWA (mesmo formato na exportação).
- **Alternativas consideradas:** Firebase/Firestore (offline nativo no Android, mas suporte no Windows marcado como "para desenvolvimento");
  Supabase self-hosted (mais manutenção); manter Google Sheets em app nativo (continua o limite de 7 dias do modo Teste).
- **Consequências:**
  - Contas criadas à mão no painel do Supabase; cadastro público desligado.
  - Plano gratuito: o projeto pausa após 7 dias sem uso e não tem backup para download → exportar backup de vez em quando.

## 2026-10-05 — Modelo de dados e sincronização
- Tabelas `lares`, `membros`, `grupos` (por ano, `tipo` receita/despesa/investimento), `itens`, `valores` (item × mês).
- IDs UUID gerados no aparelho (permite criar offline).
- `updated_at` é definido pelo servidor (trigger). O app busca "alterados desde o último cursor − 2 min" (a margem cobre
  transações que terminam fora de ordem; aplicar de novo é idempotente).
- **Valores por célula** (upsert em `(item_id, mes)`): duas pessoas lançando ao mesmo tempo não se sobrescrevem.
  Na mesma célula, vence a última gravação que chega ao servidor.
- Linhas com alteração local ainda na fila não são sobrescritas pelo que vem do servidor.
- **Exclusão lógica** (`excluido = true`): sem DELETE, para a exclusão chegar a todos os aparelhos. Não há política de DELETE no RLS.
- Acesso por **lar**: só membros leem/gravam (`e_membro()` em todas as políticas). Entrar num lar: RPC `entrar_no_lar(codigo)`.
- Nomes de grupo **não** precisam mais ser únicos (o Resumo da planilha somava por nome; agora soma por ID).

## Herdadas da v1 (continuam valendo)
- Valor consolidado por item/mês (sem lançamentos individuais com data).
- Regras de cálculo: Despesas incluem investimentos; Gasto real = Despesas − Investimentos; Média = total ÷ meses com lançamento.
- Gráficos desenhados à mão (CustomPainter), sem biblioteca de gráficos.
