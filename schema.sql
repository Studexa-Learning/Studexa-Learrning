-- Studexa Learning / shared Supabase schema (collision-safe edition)
-- Safe to use inside a Supabase project that may already contain tables such as public.profiles.
-- All Studexa-owned objects are prefixed with studexa_ so they do not overwrite another app.
-- Re-running this file is intended to be safe.

create extension if not exists pgcrypto;

-- ENUM TYPES ---------------------------------------------------------------
do $$ begin
  create type public.studexa_app_role as enum ('platform_manager','school_admin','teacher','student');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.studexa_subject as enum ('maths','science');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.studexa_gcse_tier as enum ('foundation','higher','not_applicable');
exception when duplicate_object then null;
end $$;

-- CORE TABLES --------------------------------------------------------------
create table if not exists public.studexa_school_requests (
  id uuid primary key default gen_random_uuid(),
  school_name text not null,
  school_type text,
  admin_name text not null,
  admin_email text not null,
  website text,
  estimated_students integer,
  wants_maths boolean default true,
  wants_science boolean default true,
  microsoft_requested boolean default false,
  microsoft_domain text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create table if not exists public.studexa_schools (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  status text not null default 'active',
  maths_enabled boolean not null default false,
  science_enabled boolean not null default false,
  microsoft_sso_enabled boolean not null default false,
  microsoft_domain text,
  microsoft_tenant_id text,
  created_at timestamptz not null default now()
);

-- One-time activation tokens. Production code should only store token hashes.
create table if not exists public.studexa_school_activation_tokens (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.studexa_schools(id) on delete cascade,
  admin_email text not null,
  token_hash text not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

-- IMPORTANT: Studexa uses studexa_profiles, NOT public.profiles.
-- This avoids clashing with a profiles table used by another project.
create table if not exists public.studexa_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  school_id uuid references public.studexa_schools(id) on delete cascade,
  role public.studexa_app_role not null,
  first_name text,
  last_name text,
  year_group smallint check (year_group is null or year_group between 7 and 11),
  tutor_group text,
  student_external_id text,
  created_at timestamptz not null default now()
);

create table if not exists public.studexa_teacher_subject_access (
  user_id uuid references public.studexa_profiles(user_id) on delete cascade,
  subject public.studexa_subject not null,
  primary key(user_id, subject)
);

create table if not exists public.studexa_classes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.studexa_schools(id) on delete cascade,
  name text not null,
  subject public.studexa_subject not null,
  year_group smallint not null check(year_group between 7 and 11),
  tier public.studexa_gcse_tier not null default 'not_applicable',
  owner_teacher_id uuid references public.studexa_profiles(user_id),
  archived boolean not null default false,
  unique(school_id, subject, name)
);

create table if not exists public.studexa_class_members (
  class_id uuid references public.studexa_classes(id) on delete cascade,
  student_id uuid references public.studexa_profiles(user_id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key(class_id, student_id)
);

create table if not exists public.studexa_curriculum_topics (
  id text primary key,
  subject public.studexa_subject not null,
  year_group smallint not null check(year_group between 7 and 11),
  title text not null,
  strand text not null,
  tier public.studexa_gcse_tier not null default 'not_applicable',
  exam_board text not null default 'Pearson Edexcel / Pearson-aligned KS3',
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists public.studexa_premade_homeworks (
  id text primary key,
  subject public.studexa_subject not null,
  topic_id text not null references public.studexa_curriculum_topics(id),
  title text not null,
  estimated_minutes integer not null default 25,
  sections jsonb not null,
  active boolean not null default true
);

create table if not exists public.studexa_homeworks (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.studexa_schools(id) on delete cascade,
  class_id uuid not null references public.studexa_classes(id) on delete cascade,
  created_by uuid not null references public.studexa_profiles(user_id),
  subject public.studexa_subject not null,
  title text not null,
  topic_id text references public.studexa_curriculum_topics(id),
  premade_id text references public.studexa_premade_homeworks(id),
  due_at timestamptz not null,
  opens_at timestamptz,
  is_extra boolean not null default false,
  auto_support_reason text,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.studexa_student_homework (
  homework_id uuid references public.studexa_homeworks(id) on delete cascade,
  student_id uuid references public.studexa_profiles(user_id) on delete cascade,
  status text not null default 'not_started',
  progress numeric not null default 0 check (progress between 0 and 100),
  accuracy numeric check (accuracy is null or accuracy between 0 and 100),
  time_spent_seconds integer not null default 0,
  completed_at timestamptz,
  primary key(homework_id, student_id)
);

create table if not exists public.studexa_topic_mastery (
  student_id uuid references public.studexa_profiles(user_id) on delete cascade,
  topic_id text references public.studexa_curriculum_topics(id) on delete cascade,
  mastery numeric not null default 0 check (mastery between 0 and 100),
  attempts integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key(student_id, topic_id)
);

create table if not exists public.studexa_school_support_rules (
  school_id uuid primary key references public.studexa_schools(id) on delete cascade,
  enabled boolean not null default false,
  mastery_threshold numeric not null default 50,
  max_extra_per_topic_per_week integer not null default 1,
  teacher_approval_required boolean not null default true
);

create table if not exists public.studexa_audit_log (
  id bigint generated always as identity primary key,
  school_id uuid references public.studexa_schools(id) on delete set null,
  actor_user_id uuid references public.studexa_profiles(user_id) on delete set null,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- HELPER FUNCTIONS ---------------------------------------------------------
create or replace function public.studexa_current_school_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select school_id
  from public.studexa_profiles
  where user_id = auth.uid()
$$;

create or replace function public.studexa_current_role()
returns public.studexa_app_role
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.studexa_profiles
  where user_id = auth.uid()
$$;

-- ROW LEVEL SECURITY -------------------------------------------------------
alter table public.studexa_profiles enable row level security;
alter table public.studexa_classes enable row level security;
alter table public.studexa_class_members enable row level security;
alter table public.studexa_homeworks enable row level security;
alter table public.studexa_student_homework enable row level security;
alter table public.studexa_topic_mastery enable row level security;

-- Drop/recreate policies so this file can safely be re-run.
drop policy if exists studexa_profiles_same_school_read on public.studexa_profiles;
create policy studexa_profiles_same_school_read
on public.studexa_profiles for select
using (
  school_id = public.studexa_current_school_id()
  or public.studexa_current_role() = 'platform_manager'
  or user_id = auth.uid()
);

drop policy if exists studexa_classes_same_school_read on public.studexa_classes;
create policy studexa_classes_same_school_read
on public.studexa_classes for select
using (
  school_id = public.studexa_current_school_id()
  or public.studexa_current_role() = 'platform_manager'
);

drop policy if exists studexa_classes_staff_manage on public.studexa_classes;
create policy studexa_classes_staff_manage
on public.studexa_classes for all
using (
  school_id = public.studexa_current_school_id()
  and public.studexa_current_role() in ('school_admin','teacher')
)
with check (school_id = public.studexa_current_school_id());

drop policy if exists studexa_homeworks_same_school_read on public.studexa_homeworks;
create policy studexa_homeworks_same_school_read
on public.studexa_homeworks for select
using (
  school_id = public.studexa_current_school_id()
  or public.studexa_current_role() = 'platform_manager'
);

drop policy if exists studexa_homeworks_staff_manage on public.studexa_homeworks;
create policy studexa_homeworks_staff_manage
on public.studexa_homeworks for all
using (
  school_id = public.studexa_current_school_id()
  and public.studexa_current_role() in ('school_admin','teacher')
)
with check (school_id = public.studexa_current_school_id());

-- Student-facing membership/homework/mastery policies.
drop policy if exists studexa_class_members_same_school_read on public.studexa_class_members;
create policy studexa_class_members_same_school_read
on public.studexa_class_members for select
using (
  exists (
    select 1 from public.studexa_classes c
    where c.id = class_id
      and (c.school_id = public.studexa_current_school_id()
           or public.studexa_current_role() = 'platform_manager')
  )
);

drop policy if exists studexa_student_homework_own_read on public.studexa_student_homework;
create policy studexa_student_homework_own_read
on public.studexa_student_homework for select
using (
  student_id = auth.uid()
  or public.studexa_current_role() in ('school_admin','teacher','platform_manager')
);

drop policy if exists studexa_topic_mastery_own_read on public.studexa_topic_mastery;
create policy studexa_topic_mastery_own_read
on public.studexa_topic_mastery for select
using (
  student_id = auth.uid()
  or public.studexa_current_role() in ('school_admin','teacher','platform_manager')
);

-- Helpful indexes ----------------------------------------------------------
create index if not exists studexa_profiles_school_idx on public.studexa_profiles(school_id);
create index if not exists studexa_classes_school_idx on public.studexa_classes(school_id);
create index if not exists studexa_homeworks_class_due_idx on public.studexa_homeworks(class_id, due_at);
create index if not exists studexa_audit_school_created_idx on public.studexa_audit_log(school_id, created_at desc);

-- Finished. Your pre-existing public.profiles table is deliberately untouched.
