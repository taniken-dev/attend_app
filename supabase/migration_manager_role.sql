-- ============================================================
-- manager（マネージャー）ロール追加 + 出欠実績管理 マイグレーション
-- ============================================================

-- 1. role CHECK 制約を更新（manager を追加、captain を削除）
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('member', 'manager', 'admin', 'coach'));

-- 2. attendance_records に実績カラムを追加
ALTER TABLE public.attendance_records
  ADD COLUMN IF NOT EXISTS result_status text
    CHECK (result_status IN (
      'present',
      'tardy',
      'absent_normal',
      'absent_emergency',
      'absent_unreported'
    )),
  ADD COLUMN IF NOT EXISTS verified_by uuid
    REFERENCES public.profiles(id) ON DELETE SET NULL;

-- 3. practice_sessions に実績確定フラグを追加
ALTER TABLE public.practice_sessions
  ADD COLUMN IF NOT EXISTS is_results_confirmed boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS results_confirmed_at timestamptz,
  ADD COLUMN IF NOT EXISTS results_confirmed_by uuid
    REFERENCES public.profiles(id) ON DELETE SET NULL;

-- 4. is_manager_or_admin() ヘルパー関数
CREATE OR REPLACE FUNCTION public.is_manager_or_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('manager', 'admin')
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_manager_or_admin() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.is_manager_or_admin() TO authenticated;

-- 5. profiles RLS: member/manager 以上が承認済み全員を SELECT できるよう更新
--    （既存の profiles_select_approved を差し替え）
DROP POLICY IF EXISTS "profiles_select_approved" ON public.profiles;
CREATE POLICY "profiles_select_approved" ON public.profiles
  FOR SELECT TO authenticated
  USING (
    is_approved = true
    OR id = auth.uid()
    OR public.is_admin()
    OR public.is_observer()
  );

-- member / manager も承認済みプロフィールを全件 SELECT できるポリシー
-- （is_admin や is_observer に含まれない通常ユーザー向け）
DROP POLICY IF EXISTS "profiles_select_member_approved" ON public.profiles;
CREATE POLICY "profiles_select_member_approved" ON public.profiles
  FOR SELECT TO authenticated
  USING (
    is_approved = true
    OR id = auth.uid()
  );

-- 6. attendance_records RLS: manager/admin が全行を UPDATE できるポリシー
DROP POLICY IF EXISTS "attendance_update_manager" ON public.attendance_records;
CREATE POLICY "attendance_update_manager" ON public.attendance_records
  FOR UPDATE TO authenticated
  USING (public.is_manager_or_admin())
  WITH CHECK (public.is_manager_or_admin());

-- manager/admin が attendance_records を全件 SELECT できるポリシー
DROP POLICY IF EXISTS "attendance_select_manager" ON public.attendance_records;
CREATE POLICY "attendance_select_manager" ON public.attendance_records
  FOR SELECT TO authenticated
  USING (public.is_manager_or_admin());

-- 7. practice_sessions: manager/admin が UPDATE できるポリシー（実績確定フラグ用）
DROP POLICY IF EXISTS "sessions_update_manager" ON public.practice_sessions;
CREATE POLICY "sessions_update_manager" ON public.practice_sessions
  FOR UPDATE TO authenticated
  USING (public.is_manager_or_admin())
  WITH CHECK (public.is_manager_or_admin());

-- 8. manager も練習セッションを SELECT できるポリシー（既存の sessions_select_admin があるが念のため）
DROP POLICY IF EXISTS "sessions_select_manager" ON public.practice_sessions;
CREATE POLICY "sessions_select_manager" ON public.practice_sessions
  FOR SELECT TO authenticated
  USING (public.is_manager_or_admin());
