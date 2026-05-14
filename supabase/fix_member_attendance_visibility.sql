-- ============================================================
-- 部員ロールが他の部員の出欠レコードを閲覧できるようにする
-- 問題: attendance_select_own ポリシーは自分のレコードのみ許可
--       部員は他メンバーの出欠状況（出席予定一覧など）が見えない
-- 解決: 承認済みメンバー全員が全出欠レコードを SELECT できるポリシーを追加
-- ============================================================

DROP POLICY IF EXISTS "attendance_select_approved_member" ON public.attendance_records;
CREATE POLICY "attendance_select_approved_member" ON public.attendance_records
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND is_approved = true
    )
  );
