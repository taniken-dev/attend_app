-- ============================================================
-- セキュリティ修正パッチ 2
-- Supabase Security Advisor 残存 WARNING の解消
-- Supabase SQL Editor にて実行してください。
-- ============================================================


-- ============================================================
-- [WARNING 修正 1] Function Search Path Mutable
-- is_observer() に SET search_path = '' を付与
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_observer()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'coach'
  );
$$;


-- ============================================================
-- [WARNING 修正 2] Public Can Execute SECURITY DEFINER
-- anon / public ロールから EXECUTE 権限を剥奪
-- ============================================================

-- is_observer: RLS ポリシー用ヘルパー。認証済みユーザーのみ実行可
REVOKE EXECUTE ON FUNCTION public.is_observer() FROM public;
REVOKE EXECUTE ON FUNCTION public.is_observer() FROM anon;
GRANT  EXECUTE ON FUNCTION public.is_observer() TO authenticated;

-- get_orphan_users: 内部で is_admin() チェック済みだが anon は不要
REVOKE EXECUTE ON FUNCTION public.get_orphan_users() FROM public;
REVOKE EXECUTE ON FUNCTION public.get_orphan_users() FROM anon;

-- is_admin_or_captain: RLS ヘルパー。anon は不要
REVOKE EXECUTE ON FUNCTION public.is_admin_or_captain() FROM public;
REVOKE EXECUTE ON FUNCTION public.is_admin_or_captain() FROM anon;

-- rls_auto_enable: ユーザーが直接呼ぶ必要はない
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM public;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM anon;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM authenticated;


-- ============================================================
-- [WARNING 参考] Leaked Password Protection
-- SQL では変更不可。Supabase Dashboard で対応:
--   Authentication → Sign In / Up → Password
--   → "Enable Leaked Password Protection" を ON にする
-- ============================================================
