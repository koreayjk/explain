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
  created_at  timestamptz not null default now()
);

-- 2) 프로필 (학생/교사 구분) -------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        text not null default 'student' check (role in ('student','teacher')),
  name        text,
  class_id    uuid references public.classes(id),
  created_at  timestamptz not null default now()
);

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
  -- LEI 5개 하위 지표 (0~100)
  coverage           int,   -- 개념 포함도
  accuracy           int,   -- 설명 정확도 (오개념 여부)
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
  transcript        text,                  -- STT 결과
  present_concepts  jsonb default '[]',    -- 포함된 핵심개념
  missing_concepts  jsonb default '[]',    -- 누락된 핵심개념
  misconceptions    jsonb default '[]',    -- 탐지된 오개념
  ai_question       text,                  -- AI 소크라테스 질문
  response_ms       int,                   -- 응답 지연(생각 시간) ms
  created_at        timestamptz not null default now()
);

-- 5) 이의 제기 (오탐 완충장치 — 리스크분석 권고 #2) -------------------------
create table if not exists public.disputes (
  id          uuid primary key default gen_random_uuid(),
  turn_id     uuid references public.turns(id) on delete cascade,
  student_id  uuid not null references public.profiles(id) on delete cascade,
  reason      text,
  created_at  timestamptz not null default now()
);

-- ============================================================
-- RLS (Row Level Security) — 학생은 본인 데이터만, 교사는 학급 데이터 열람
-- ============================================================
alter table public.profiles  enable row level security;
alter table public.classes   enable row level security;
alter table public.sessions  enable row level security;
alter table public.turns     enable row level security;
alter table public.disputes  enable row level security;

-- 프로필: 본인 것 읽기/생성/수정
drop policy if exists "own profile read"   on public.profiles;
drop policy if exists "own profile write"  on public.profiles;
drop policy if exists "own profile update" on public.profiles;
create policy "own profile read"   on public.profiles for select using (auth.uid() = id);
create policy "own profile write"  on public.profiles for insert with check (auth.uid() = id);
create policy "own profile update" on public.profiles for update using (auth.uid() = id);

-- 세션: 학생 본인 전체 권한 + 교사는 읽기
drop policy if exists "student own sessions"        on public.sessions;
drop policy if exists "teacher read class sessions" on public.sessions;
create policy "student own sessions" on public.sessions
  for all using (auth.uid() = student_id) with check (auth.uid() = student_id);
create policy "teacher read class sessions" on public.sessions
  for select using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher')
  );

-- 턴: 세션 소유자 기준
drop policy if exists "turns by owner" on public.turns;
create policy "turns by owner" on public.turns
  for all using (
    exists (select 1 from public.sessions s
            where s.id = turns.session_id and s.student_id = auth.uid())
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
