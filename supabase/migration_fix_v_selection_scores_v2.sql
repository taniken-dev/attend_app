-- ============================================================
-- v_selection_scores ビュー修正 v2
-- 変更点:
--   - 分母を「result_status が確定済みのセッション数（当日以前）」に変更
--   - 未確定セッションは分母・分子ともに除外
--   - session_date <= current_date を厳守
-- ============================================================

CREATE OR REPLACE VIEW public.v_selection_scores
  WITH (security_invoker = on)
AS
WITH session_stats AS (
  SELECT
    ar.user_id,
    -- 分母: result_status が確定済みかつ当日以前の非キャンセルセッション数
    count(*) FILTER (WHERE ar.result_status IS NOT NULL
                       AND ps.session_date <= current_date
                       AND ps.is_cancelled = false)                   AS total_sessions,
    count(*) FILTER (WHERE ar.result_status = 'present'
                       AND ps.session_date <= current_date
                       AND ps.is_cancelled = false)                   AS present_count,
    count(*) FILTER (WHERE ar.result_status = 'tardy'
                       AND ps.session_date <= current_date
                       AND ps.is_cancelled = false)                   AS tardy_count,
    count(*) FILTER (WHERE ar.result_status IN ('absent_normal','absent_emergency','absent_unreported')
                       AND ps.session_date <= current_date
                       AND ps.is_cancelled = false)                   AS absent_count,
    count(*) FILTER (WHERE ar.result_status = 'absent_emergency'
                       AND ps.session_date <= current_date
                       AND ps.is_cancelled = false)                   AS emergency_count,
    count(*) FILTER (WHERE ar.result_status = 'absent_unreported'
                       AND ps.session_date <= current_date
                       AND ps.is_cancelled = false)                   AS unreported_count
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
    coalesce(ss.total_sessions,   0)  AS total_sessions,
    coalesce(ss.present_count,    0)  AS present_count,
    coalesce(ss.tardy_count,      0)  AS tardy_count,
    coalesce(ss.absent_count,     0)  AS absent_count,
    coalesce(ss.emergency_count,  0)  AS emergency_count,
    CASE
      WHEN coalesce(ss.total_sessions, 0) = 0 THEN 100.0
      ELSE round(
        (coalesce(ss.present_count, 0) + coalesce(ss.tardy_count, 0) * 0.5)::numeric
        / coalesce(ss.total_sessions, 1) * 100,
        1
      )
    END AS attendance_rate,
    round(
      (p.skill_rank::numeric / 6.0)
      * CASE
          WHEN coalesce(ss.total_sessions, 0) = 0 THEN 1.0
          ELSE (coalesce(ss.present_count, 0) + coalesce(ss.tardy_count, 0) * 0.5)
               / coalesce(ss.total_sessions, 1)
        END
      * 100, 1
    ) AS selection_score,
    coalesce(ss.unreported_count, 0)  AS unreported_count
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
  attendance_rate,
  selection_score,
  CASE
    WHEN attendance_rate >= 85 THEN 'S'
    WHEN attendance_rate >= 70 THEN 'A'
    WHEN attendance_rate >= 55 THEN 'B'
    WHEN attendance_rate >= 40 THEN 'C'
    WHEN attendance_rate >= 25 THEN 'D'
    ELSE 'E'
  END AS selection_rank,
  unreported_count
FROM calc
ORDER BY attendance_rate DESC, present_count DESC;
