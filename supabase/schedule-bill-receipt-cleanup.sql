-- Replace the cleanup-secret placeholder before running. Run once per Supabase project.
create extension if not exists pg_cron;
create extension if not exists pg_net;
create extension if not exists supabase_vault with schema vault;

select vault.create_secret(
  'https://ztxbyqgqtibgnsepjmzf.supabase.co',
  'bill_cleanup_project_url'
);
select vault.create_secret(
  'sb_publishable_dGmwD-ACC4wlneOnEW06Xg_XVg4pOt-',
  'bill_cleanup_publishable_key'
);
select vault.create_secret(
  'REPLACE_WITH_BILL_RECEIPT_CLEANUP_SECRET',
  'bill_cleanup_secret'
);

select cron.schedule(
  'delete-expired-bill-receipts',
  '0 3 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'bill_cleanup_project_url')
      || '/functions/v1/cleanup-bill-receipts',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'bill_cleanup_publishable_key'),
      'x-cleanup-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'bill_cleanup_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);
