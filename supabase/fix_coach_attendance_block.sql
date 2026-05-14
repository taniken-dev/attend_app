-- ============================================================
-- 顧問（coach）ロールの出欠登録を完全禁止するマイグレーション
-- ・顧問自身による自己登録を禁止
-- ・manager/admin による顧問への実績登録を禁止
-- ============================================================

-- 1. attendance_insert_own: 顧問は自分のレコードも INSERT 不可
DROP POLICY IF EXISTS "attendance_insert_own" ON public.attendance_records;
CREATE POLICY "attendance_insert_own" ON public.attendance_records
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND NOT public.is_observer()
  );

-- 2. attendance_insert_manager: manager/admin が INSERT する際、対象ユーザーが顧問でないこと
DROP POLICY IF EXISTS "attendance_insert_manager" ON public.attendance_records;
CREATE POLICY "attendance_insert_manager" ON public.attendance_records
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_manager_or_admin()
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = user_id AND role = 'coach'
    )
  );

-- 3. attendance_update_manager: manager/admin が UPDATE する際、対象ユーザーが顧問でないこと
DROP POLICY IF EXISTS "attendance_update_manager" ON public.attendance_records;
CREATE POLICY "attendance_update_manager" ON public.attendance_records
  FOR UPDATE TO authenticated
  USING (
    public.is_manager_or_admin()
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = user_id AND role = 'coach'
    )
  )
  WITH CHECK (
    public.is_manager_or_admin()
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = user_id AND role = 'coach'
    )
  );
