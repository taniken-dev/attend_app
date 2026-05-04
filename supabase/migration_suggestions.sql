-- ============================================================
-- suggestions（ご意見箱）テーブル マイグレーション
-- 匿名投稿のため user_id は保存しない
-- ============================================================

CREATE TABLE IF NOT EXISTS public.suggestions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title      text NOT NULL,
  body       text NOT NULL,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.suggestions ENABLE ROW LEVEL SECURITY;

-- 認証済みユーザーは誰でも投稿可（匿名性担保）
CREATE POLICY "suggestions_insert"
  ON public.suggestions
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- 管理者のみ閲覧可
CREATE POLICY "suggestions_select_admin"
  ON public.suggestions
  FOR SELECT
  TO authenticated
  USING (public.is_admin());
