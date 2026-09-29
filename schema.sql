-- Studexa shared Supabase schema (starter)
-- Designed for one database shared by Studexa Learning, Maths and Science.
-- IMPORTANT: production deployment requires review of all RLS policies and mail/OAuth configuration.

create extension if not exists pgcrypto;

create type public.studexa_role as enum ('platform_manager','school_admin','teacher','student');
create type public.subject_code as enum ('maths','science');
create type public.gcse_tier as enum ('foundation','higher','not_applicable');

create table public.school_requests (
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

create table public.schools (
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

-- One-time activation tokens: store hash only, never plaintext.
create table public.school_activation_tokens (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  admin_email text not null,
  token_hash text not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  school_id uuid references public.schools(id) on delete cascade,
  role public.studexa_role not null,
  first_name text,
  last_name text,
  year_group smallint,
  tutor_group text,
  student_external_id text,
  created_at timestamptz not null default now()
);

create table public.teacher_subject_access (
  user_id uuid references public.profiles(user_id) on delete cascade,
  subject public.subject_code not null,
  primary key(user_id,subject)
);

create table public.classes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  name text not null,
  subject public.subject_code not null,
  year_group smallint not null check(year_group between 7 and 11),
  tier public.gcse_tier not null default 'not_applicable',
  owner_teacher_id uuid references public.profiles(user_id),
  archived boolean not null default false,
  unique(school_id,subject,name)
);

create table public.class_members (
  class_id uuid references public.classes(id) on delete cascade,
  student_id uuid references public.profiles(user_id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key(class_id,student_id)
);

create table public.curriculum_topics (
  id text primary key,
  subject public.subject_code not null,
  year_group smallint not null,
  title text not null,
  strand text not null,
  tier public.gcse_tier not null default 'not_applicable',
  exam_board text not null default 'Pearson Edexcel / Pearson-aligned KS3',
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb
);

create table public.premade_homeworks (
  id text primary key,
  subject public.subject_code not null,
  topic_id text not null references public.curriculum_topics(id),
  title text not null,
  estimated_minutes integer not null default 25,
  sections jsonb not null,
  active boolean not null default true
);

create table public.homeworks (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  created_by uuid not null references public.profiles(user_id),
  subject public.subject_code not null,
  title text not null,
  topic_id text references public.curriculum_topics(id),
  premade_id text references public.premade_homeworks(id),
  due_at timestamptz not null,
  opens_at timestamptz,
  is_extra boolean not null default false,
  auto_support_reason text,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.student_homework (
  homework_id uuid references public.homeworks(id) on delete cascade,
  student_id uuid references public.profiles(user_id) on delete cascade,
  status text not null default 'not_started',
  progress numeric not null default 0,
  accuracy numeric,
  time_spent_seconds integer not null default 0,
  completed_at timestamptz,
  primary key(homework_id,student_id)
);

create table public.topic_mastery (
  student_id uuid references public.profiles(user_id) on delete cascade,
  topic_id text references public.curriculum_topics(id) on delete cascade,
  mastery numeric not null default 0,
  attempts integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key(student_id,topic_id)
);

create table public.school_support_rules (
  school_id uuid primary key references public.schools(id) on delete cascade,
  enabled boolean not null default false,
  mastery_threshold numeric not null default 50,
  max_extra_per_topic_per_week integer not null default 1,
  teacher_approval_required boolean not null default true
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  school_id uuid references public.schools(id) on delete set null,
  actor_user_id uuid references public.profiles(user_id) on delete set null,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- RLS baseline
alter table public.profiles enable row level security;
alter table public.classes enable row level security;
alter table public.class_members enable row level security;
alter table public.homeworks enable row level security;
alter table public.student_homework enable row level security;
alter table public.topic_mastery enable row level security;

create or replace function public.current_school_id() returns uuid language sql stable security definer as $$
  select school_id from public.profiles where user_id = auth.uid()
$$;
create or replace function public.current_role() returns public.studexa_role language sql stable security definer as $$
  select role from public.profiles where user_id = auth.uid()
$$;

create policy "profiles_same_school_read" on public.profiles for select using (
  school_id = public.current_school_id() or public.current_role()='platform_manager'
);
create policy "classes_same_school_read" on public.classes for select using (
  school_id = public.current_school_id() or public.current_role()='platform_manager'
);
create policy "classes_staff_manage" on public.classes for all using (
  school_id = public.current_school_id() and public.current_role() in ('school_admin','teacher')
) with check (school_id = public.current_school_id());
create policy "homeworks_same_school_read" on public.homeworks for select using (
  school_id = public.current_school_id() or public.current_role()='platform_manager'
);
create policy "homeworks_staff_manage" on public.homeworks for all using (
  school_id = public.current_school_id() and public.current_role() in ('school_admin','teacher')
) with check (school_id = public.current_school_id());
