-- ============================================================
-- v_selection_scores ビュー修正 v3
-- 変更点（v2からの修正）:
--   - 分母を「全体の確定済みセッション数」に統一（v2では per-user だったため
--     未提出欠席が分母から除外され出席率が過大評価される問題を修正）
--   - 確定済みセッションが0件の場合は 0.0% を返す（v2 の 100% バグを修正）
-- ============================================================

DROP VIEW IF EXISTS public.v_selection_scores;

CREATE VIEW public.v_selection_scores
  WITH (security_invoker = on)
AS
WITH all_sessions AS (
  -- 全体の確定済みセッション数（全員共通の分母）
  SELECT count(*) AS total
  FROM public.practice_sessions
  WHERE session_date <= current_date
    AND is_cancelled = false
    AND is_results_confirmed = true
),
session_stats AS (
  -- ユーザーごとの result_status 集計（確定済みセッションのみ）
  SELECT
    ar.user_id,
    count(*) FILTER (WHERE ar.result_status = 'present'
                       AND ps.session_date <= current_date
                       AND ps.is_cancelled = false
                       AND ps.is_results_confirmed = true)            AS present_count,
    count(*) FILTER (WHERE ar.result_status = 'tardy'
                       AND ps.session_date <= current_date
                       AND ps.is_cancelled = false
                       AND ps.is_results_confirmed = true)            AS tardy_count,
    count(*) FILTER (WHERE ar.result_status IN ('absent_normal','absent_emergency','absent_unreported')
                       AND ps.session_date <= current_date
                       AND ps.is_cancelled = false
                       AND ps.is_results_confirmed = true)            AS absent_count,
    count(*) FILTER (WHERE ar.result_status = 'absent_emergency'
                       AND ps.session_date <= current_date
                       AND ps.is_cancelled = false
                       AND ps.is_results_confirmed = true)            AS emergency_count,
    count(*) FILTER (WHERE ar.result_status = 'absent_unreported'
                       AND ps.session_date <= current_date
                       AND ps.is_cancelled = false
                       AND ps.is_results_confirmed = true)            AS unreported_count
  FROM public.attendance_records ar
  JOIN public.practice_sessions ps ON ps.id = ar.session_id
  GROUP BY ar.user_id
),
calc AS (
  SELECT
    p.id,
    p.full_name,
    p.display_name,
    p.grade,
    p.gender,
    p.skill_rank,
    (SELECT total FROM all_sessions)       AS total_sessions,
    coalesce(ss.present_count,    0)       AS present_count,
    coalesce(ss.tardy_count,      0)       AS tardy_count,
    coalesce(ss.absent_count,     0)       AS absent_count,
    coalesce(ss.emergency_count,  0)       AS emergency_count,
    coalesce(ss.unreported_count, 0)       AS unreported_count,
    -- 出席率: 確定済みセッションが0件なら 0%
    CASE
      WHEN (SELECT total FROM all_sessions) = 0 THEN 0.0
      ELSE round(
        (coalesce(ss.present_count, 0) + coalesce(ss.tardy_count, 0) * 0.5)::numeric
        / (SELECT total FROM all_sessions) * 100,
        1
      )
    END AS attendance_rate,
    -- 選考スコア
    CASE
      WHEN (SELECT total FROM all_sessions) = 0 THEN 0.0
      ELSE round(
        (p.skill_rank::numeric / 6.0)
        * (coalesce(ss.present_count, 0) + coalesce(ss.tardy_count, 0) * 0.5)
        / (SELECT total FROM all_sessions) * 100,
        1
      )
    END AS selection_score
  FROM public.profiles p
  LEFT JOIN session_stats ss ON ss.user_id = p.id
  WHERE p.is_approved = true
)
SELECT
  id,
  full_name,
  display_name,
  grade,
  gender,
  skill_rank,
  total_sessions,
  present_count,
  tardy_count,
  absent_count,
  emergency_count,
  unreported_count,
  attendance_rate,
  selection_score,
  CASE
    WHEN attendance_rate >= 85 THEN 'S'
    WHEN attendance_rate >= 70 THEN 'A'
    WHEN attendance_rate >= 55 THEN 'B'
    WHEN attendance_rate >= 40 THEN 'C'
    WHEN attendance_rate >= 25 THEN 'D'
    ELSE 'E'
  END AS selection_rank
FROM calc
ORDER BY attendance_rate DESC, present_count DESC;
