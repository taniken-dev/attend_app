-- profiles に joined_at カラムを追加
-- NULL の場合はアプリ側・ビュー側で学年から自動計算する
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS joined_at DATE;
