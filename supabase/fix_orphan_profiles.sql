-- ============================================================
-- 孤立ユーザー（auth.users にあるが profiles がない）の根本修正
-- 問題:
--   1. handle_new_user トリガーに EXCEPTION ハンドラーがなく
--      INSERT 失敗時にユーザー作成ごとロールバックされる場合がある
--      → 実際には auth.users に残るが profiles が作られないケースが発生
--   2. 孤立ユーザーは profiles ベースの管理画面から完全に不可視
-- ============================================================

-- ① トリガー関数を堅牢化（EXCEPTION ハンドラー追加）
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (
    id, full_name, avatar_url, grade, role, skill_rank, is_approved
  ) VALUES (
    new.id,
    COALESCE(
      NULLIF(TRIM(new.raw_user_meta_data->>'full_name'), ''),
      NULLIF(TRIM(new.raw_user_meta_data->>'name'), ''),
      NULLIF(TRIM(split_part(new.email, '@', 1)), ''),
      '新規ユーザー'
    ),
    COALESCE(
      new.raw_user_meta_data->>'avatar_url',
      new.raw_user_meta_data->>'picture'
    ),
    COALESCE((new.raw_user_meta_data->>'grade')::int, 1),
    'member',
    3,
    false
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
EXCEPTION WHEN OTHERS THEN
  -- プロフィール作成に失敗してもユーザー作成は継続
  -- 孤立ユーザーは get_orphan_users() で後から検出・修正可能
  RAISE WARNING 'handle_new_user: profile creation failed for user %: %', new.id, SQLERRM;
  RETURN new;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM public, anon, authenticated;

-- ② 既存の孤立ユーザーを一括で profiles に追加（is_approved=false で承認待ち扱い）
INSERT INTO public.profiles (id, full_name, avatar_url, grade, role, skill_rank, is_approved)
SELECT
  u.id,
  COALESCE(
    NULLIF(TRIM(u.raw_user_meta_data->>'full_name'), ''),
    NULLIF(TRIM(u.raw_user_meta_data->>'name'), ''),
    NULLIF(TRIM(split_part(u.email, '@', 1)), ''),
    '新規ユーザー'
  ),
  COALESCE(
    u.raw_user_meta_data->>'avatar_url',
    u.raw_user_meta_data->>'picture'
  ),
  1,
  'member',
  3,
  false
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- ③ 管理者が孤立ユーザーを検出できる SECURITY DEFINER 関数
CREATE OR REPLACE FUNCTION public.get_orphan_users()
RETURNS TABLE(
  id         uuid,
  email      text,
  created_at timestamptz,
  full_name  text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u.email::text,
    u.created_at,
    COALESCE(
      NULLIF(TRIM(u.raw_user_meta_data->>'full_name'), ''),
      NULLIF(TRIM(u.raw_user_meta_data->>'name'), ''),
      NULLIF(TRIM(split_part(u.email, '@', 1)), ''),
      '不明'
    ) AS full_name
  FROM auth.users u
  LEFT JOIN public.profiles p ON p.id = u.id
  WHERE p.id IS NULL
  ORDER BY u.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_orphan_users() TO authenticated;
