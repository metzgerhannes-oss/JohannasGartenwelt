insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'jgw-photos',
  'jgw-photos',
  false,
  5242880,
  array['image/jpeg','image/webp','image/png']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;