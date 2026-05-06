-- ============================================================
-- セキュリティ修正：自己ロール昇格・自己承認の防止
-- profiles_update_own ポリシーは role / is_approved カラムの
-- 更新を制限していないため、任意の部員が自身を admin に昇格
-- できる脆弱性がある。トリガーで防止する。
-- Supabase SQL Editor にて実行してください。
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_privilege_escalation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- 呼び出し元が admin かどうか確認
  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  ) THEN
    -- admin は全カラム変更可
    RETURN NEW;
  END IF;

  -- 非 admin が role を変更しようとした場合は拒否
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    RAISE EXCEPTION 'Role changes require admin privileges';
  END IF;

  -- 非 admin が is_approved を変更しようとした場合は拒否
  IF NEW.is_approved IS DISTINCT FROM OLD.is_approved THEN
    RAISE EXCEPTION 'Approval changes require admin privileges';
  END IF;

  RETURN NEW;
END;
$$;

-- 既存トリガーがあれば削除して再作成
DROP TRIGGER IF EXISTS prevent_privilege_escalation ON public.profiles;

CREATE TRIGGER prevent_privilege_escalation
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_privilege_escalation();

-- トリガー関数の実行権限を制限（トリガー経由でのみ呼ばれる）
REVOKE EXECUTE ON FUNCTION public.prevent_privilege_escalation() FROM public;
REVOKE EXECUTE ON FUNCTION public.prevent_privilege_escalation() FROM anon;
REVOKE EXECUTE ON FUNCTION public.prevent_privilege_escalation() FROM authenticated;
