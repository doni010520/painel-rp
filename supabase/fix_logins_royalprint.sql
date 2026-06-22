-- ============================================================================
-- CORREÇÃO dos logins (Auth) — rodar UMA vez no SQL Editor.
-- Sintoma: Auth retorna 500 "Database error finding users" e o login falha como
-- "usuário ou senha inválidos", mesmo com a senha correta.
-- Causa: usuários inseridos via SQL ficaram com colunas de token em NULL; o
-- Supabase Auth exige string vazia ('') nelas. Este script corrige só o que existe.
-- ============================================================================
do $$
declare
  col text;
  cols text[] := array[
    'confirmation_token','recovery_token','email_change','email_change_token_new',
    'email_change_token_current','phone_change','phone_change_token','reauthentication_token'
  ];
begin
  foreach col in array cols loop
    if exists (
      select 1 from information_schema.columns
      where table_schema='auth' and table_name='users' and column_name=col
    ) then
      execute format(
        'update auth.users set %I = coalesce(%I, '''') where email like ''%%@royalprint.com.br''',
        col, col
      );
    end if;
  end loop;
end $$;

-- Conferência: deve listar os 5 usuários sem erro.
select email, (email_confirmed_at is not null) as confirmado
from auth.users
where email like '%@royalprint.com.br'
order by email;
