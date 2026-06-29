-- ============================================================
-- EXPLAIN_A · Supabase 스키마
-- Supabase 프로젝트 > SQL Editor 에 붙여넣고 실행하세요.
-- 여러 번 실행해도 안전(idempotent)하도록 작성됨.
-- ============================================================

-- 1) 학급 (teacher_id FK는 순환 참조라 아래에서 ALTER로 추가) -----------------
create table if not exists public.classes (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  teacher_id  uuid,            -- → profiles(id) (아래 ALTER에서 연결)
  join_code   text unique,     -- 학생이 반에 참여할 때 입력하는 코드
  created_at  timestamptz not null default now()
);
-- 기존 테이블에 join_code가 없으면 추가
alter table public.classes add column if not exists join_code text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'classes_join_code_key') then
    alter table public.classes add constraint classes_join_code_key unique (join_code);
  end if;
end $$;

-- 2) 프로필 (역할: 학생/교사/학부모/원장) ------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        text not null default 'student',
  name        text,
  class_id    uuid references public.classes(id),
  created_at  timestamptz not null default now()
);
-- 역할 4종으로 확장 (기존 제약 갱신)
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('student','teacher','parent','admin'));

-- classes.teacher_id → profiles(id) 연결 (이제 profiles 존재) -----------------
alter table public.classes drop constraint if exists classes_teacher_fk;
alter table public.classes
  add constraint classes_teacher_fk
  foreign key (teacher_id) references public.profiles(id) on delete set null;

-- 3) 학습 세션 (한 번의 설명 학습 = LEI 1건) --------------------------------
create table if not exists public.sessions (
  id                 uuid primary key default gen_random_uuid(),
  student_id         uuid not null references public.profiles(id) on delete cascade,
  topic              text not null,
  coverage           int,   -- 개념 포함도
  accuracy           int,   -- 설명 정확도
  speed              int,   -- 응답 속도
  extension          int,   -- 설명 확장성
  question_response  int,   -- 질문 대응력
  lei                int,   -- 종합 LEI (5개 평균)
  level              int,   -- 추정 학습 레벨 (1~5)
  feedback           text,
  created_at         timestamptz not null default now()
);

-- 4) 턴 (세션 내부의 설명/질문 단위) ----------------------------------------
create table if not exists public.turns (
  id                uuid primary key default gen_random_uuid(),
  session_id        uuid not null references public.sessions(id) on delete cascade,
  turn_no           int not null,
  transcript        text,
  present_concepts  jsonb default '[]',
  missing_concepts  jsonb default '[]',
  misconceptions    jsonb default '[]',
  ai_question       text,
  response_ms       int,
  created_at        timestamptz not null default now()
);

-- 5) 이의 제기 (오탐 완충장치) ----------------------------------------------
create table if not exists public.disputes (
  id          uuid primary key default gen_random_uuid(),
  turn_id     uuid references public.turns(id) on delete cascade,
  student_id  uuid not null references public.profiles(id) on delete cascade,
  reason      text,
  created_at  timestamptz not null default now()
);

-- ============================================================
-- 헬퍼 함수 (RLS에서 재귀 없이 권한 판정 — SECURITY DEFINER)
-- ============================================================
-- 교사가 해당 학생을 담당하는가? (내 반에 속한 학생인가)
create or replace function public.teacher_owns_student(stu uuid)
returns boolean language sql security definer stable as $$
  select exists (
    select 1 from public.profiles p
    join public.classes c on c.id = p.class_id
    where p.id = stu and c.teacher_id = auth.uid()
  );
$$;

-- 학생이 코드로 반에 참여 (RLS 우회하여 본인 class_id 설정)
create or replace function public.join_class(p_code text)
returns text language plpgsql security definer as $$
declare c record;
begin
  select id, name into c from public.classes where join_code = upper(trim(p_code));
  if not found then raise exception '존재하지 않는 반 코드입니다.'; end if;
  update public.profiles set class_id = c.id where id = auth.uid();
  return c.name;
end; $$;

-- ============================================================
-- RLS — 학생은 본인 / 교사는 담당 반 / 모두 격리
-- ============================================================
alter table public.profiles  enable row level security;
alter table public.classes   enable row level security;
alter table public.sessions  enable row level security;
alter table public.turns     enable row level security;
alter table public.disputes  enable row level security;

-- 프로필: 본인 읽기/생성/수정 + 교사는 담당 반 학생 읽기
drop policy if exists "own profile read"   on public.profiles;
drop policy if exists "own profile write"  on public.profiles;
drop policy if exists "own profile update" on public.profiles;
drop policy if exists "teacher read students" on public.profiles;
create policy "own profile read"   on public.profiles for select using (auth.uid() = id);
create policy "own profile write"  on public.profiles for insert with check (auth.uid() = id);
create policy "own profile update" on public.profiles for update using (auth.uid() = id);
create policy "teacher read students" on public.profiles
  for select using (public.teacher_owns_student(id));

-- 반: 교사는 본인 반 전체 권한 + 본인이 속한 반 읽기(학생이 반 이름 확인)
drop policy if exists "teacher own classes" on public.classes;
drop policy if exists "read own class"      on public.classes;
create policy "teacher own classes" on public.classes
  for all using (teacher_id = auth.uid()) with check (teacher_id = auth.uid());
create policy "read own class" on public.classes
  for select using (
    id in (select class_id from public.profiles where id = auth.uid())
  );

-- 세션: 학생 본인 전체 권한 + 교사는 담당 반 학생 읽기
drop policy if exists "student own sessions"        on public.sessions;
drop policy if exists "teacher read class sessions" on public.sessions;
create policy "student own sessions" on public.sessions
  for all using (auth.uid() = student_id) with check (auth.uid() = student_id);
create policy "teacher read class sessions" on public.sessions
  for select using (public.teacher_owns_student(student_id));

-- 턴: 세션 소유자 + 교사는 담당 반 학생 읽기
drop policy if exists "turns by owner"        on public.turns;
drop policy if exists "teacher read turns"    on public.turns;
create policy "turns by owner" on public.turns
  for all using (
    exists (select 1 from public.sessions s
            where s.id = turns.session_id and s.student_id = auth.uid())
  );
create policy "teacher read turns" on public.turns
  for select using (
    exists (select 1 from public.sessions s
            where s.id = turns.session_id and public.teacher_owns_student(s.student_id))
  );

-- 이의 제기: 본인 것
drop policy if exists "disputes by owner" on public.disputes;
create policy "disputes by owner" on public.disputes
  for all using (auth.uid() = student_id) with check (auth.uid() = student_id);

-- ============================================================
-- 신규 가입 시 profiles 자동 생성 (role 은 메타데이터에서)
-- ============================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, role, name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'role', 'student'),
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1))
  )
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
