-- =====================================================================
--  PUNTOS DE ACOPIO · VENEZUELA  —  Configuración de Supabase
--  Pega todo este archivo en:  Supabase -> SQL Editor -> New query -> Run
-- =====================================================================

-- 1) TABLA -------------------------------------------------------------
create table if not exists public.puntos_acopio (
  id           uuid primary key default gen_random_uuid(),
  nombre       text not null,
  direccion    text not null,
  ciudad       text not null,
  provincia    text,
  contacto     text not null,
  whatsapp     text,                          -- solo dígitos, para wa.me
  horario      text not null,
  necesidades  text,
  estado       text not null default 'recibiendo'
                 check (estado in ('recibiendo','completo','pausado')),
  verificado   boolean not null default false, -- lo activas tú al revisar
  oficial      boolean not null default false, -- punto institucional/oficial, gestionado solo por el administrador
  edit_token   text not null,                  -- código privado de gestión
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists idx_puntos_orden on public.puntos_acopio (oficial desc, verificado desc, updated_at desc);

-- Si la tabla ya existía antes de añadir "oficial", ejecuta también:
-- alter table public.puntos_acopio add column if not exists oficial boolean not null default false;

-- 2) RLS: la tabla NO es legible directamente (así el token queda oculto)
alter table public.puntos_acopio enable row level security;

-- Permitir que cualquiera (anon) inserte un punto, pero sin auto-verificarse
drop policy if exists "insert_publico" on public.puntos_acopio;
create policy "insert_publico"
  on public.puntos_acopio
  for insert
  to anon, authenticated
  with check (verificado = false);

grant insert on public.puntos_acopio to anon, authenticated;

-- 3) VISTA PÚBLICA: lectura sin exponer edit_token ---------------------
create or replace view public.puntos_publicos as
  select id, nombre, direccion, ciudad, provincia, contacto, whatsapp,
         horario, necesidades, estado, verificado, oficial, created_at, updated_at
  from public.puntos_acopio;

grant select on public.puntos_publicos to anon, authenticated;

-- 4) FUNCIÓN: cargar un punto para editar, validando el token ----------
create or replace function public.buscar_punto_por_token(p_token text)
returns table (
  id uuid, nombre text, direccion text, ciudad text, provincia text,
  contacto text, whatsapp text, horario text, necesidades text, estado text
)
language sql
security definer
set search_path = public
as $$
  select id, nombre, direccion, ciudad, provincia, contacto, whatsapp,
         horario, necesidades, estado
  from public.puntos_acopio
  where edit_token = p_token
  limit 1;
$$;

grant execute on function public.buscar_punto_por_token(text) to anon, authenticated;

-- 5) FUNCIÓN: actualizar un punto, solo si el token coincide -----------
create or replace function public.actualizar_punto(
  p_token       text,
  p_estado      text,
  p_necesidades text,
  p_horario     text,
  p_contacto    text,
  p_whatsapp    text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  select id into v_id from public.puntos_acopio where edit_token = p_token;
  if v_id is null then
    return false;
  end if;

  update public.puntos_acopio set
    estado      = coalesce(nullif(p_estado, ''), estado),
    necesidades = nullif(p_necesidades, ''),
    horario     = coalesce(nullif(p_horario, ''), horario),
    contacto    = coalesce(nullif(p_contacto, ''), contacto),
    whatsapp    = nullif(p_whatsapp, ''),
    updated_at  = now()
  where id = v_id;

  return true;
end;
$$;

grant execute on function public.actualizar_punto(text,text,text,text,text,text) to anon, authenticated;

-- =====================================================================
--  MODERACIÓN (desde el panel de Supabase -> Table editor)
--  · Verificar un punto:   update puntos_acopio set verificado = true where id = '...';
--  · Marcar como oficial:  update puntos_acopio set oficial = true, verificado = true where id = '...';
--  · Eliminar spam:        delete from puntos_acopio where id = '...';
-- =====================================================================

-- =====================================================================
--  PLANTILLA: alta de un punto oficial
--  Los puntos oficiales se publican siempre verificados y con oficial=true,
--  y aparecen por encima del resto en el listado. Genera un edit_token
--  único (p.ej. con gen_random_uuid()::text) para poder actualizarlos.
-- =====================================================================
-- insert into public.puntos_acopio
--   (nombre, direccion, ciudad, provincia, contacto, whatsapp, horario, necesidades, estado, verificado, oficial, edit_token)
-- values
--   ('Nombre del punto oficial', 'Dirección completa', 'Ciudad', 'Provincia',
--    '+34 600 000 000', '34600000000', 'Horario de atención',
--    'Qué se necesita actualmente', 'recibiendo', true, true, gen_random_uuid()::text);
