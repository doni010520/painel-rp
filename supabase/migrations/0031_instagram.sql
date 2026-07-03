-- 0031 — Canal Instagram (DM). Permite type='instagram' em channels.
alter table channels drop constraint if exists channels_type_check;
alter table channels add  constraint channels_type_check
  check (type in ('meta_cloud','uazapi','instagram'));
