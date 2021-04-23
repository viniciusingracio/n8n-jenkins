WITH C1 AS
(
  SELECT
    MIN(join_time) AS tss,
    +1 AS TYPE,
    meeting_id,
    unique_name,
    ROW_NUMBER() OVER(ORDER BY MIN(join_time)) AS start_ordinal
  FROM (
    SELECT
      *,
      LEAST(leave_time, end_time) AS leave_time2
    FROM users JOIN meetings ON users.meeting_id = meetings.id
    WHERE ( leave_time IS NOT NULL OR end_time IS NOT NULL ) AND is_breakout = false AND test_meeting = false
  ) t -- this is required because leave_time might be null
  GROUP BY meeting_id, unique_name

  UNION ALL

  SELECT
    MAX(leave_time2),
    -1,
    meeting_id,
    unique_name,
    NULL
  FROM (
    SELECT
      *,
      LEAST(leave_time, end_time) AS leave_time2
    FROM users JOIN meetings ON users.meeting_id = meetings.id
    WHERE ( leave_time IS NOT NULL OR end_time IS NOT NULL ) AND is_breakout = false AND test_meeting = false
  ) t -- this is required because leave_time might be null
  GROUP BY meeting_id, unique_name
),
C2 AS
(
  SELECT
    *,
    ROW_NUMBER() OVER(  ORDER BY tss, TYPE ) AS start_or_end_ordinal
  FROM C1
)
SELECT
  TO_CHAR(TO_TIMESTAMP(tss / 1000)::timestamp at time zone 'utc' at time zone 'america/sao_paulo', 'YYYY-MM-DD') AS "date",
  MAX(2 * start_ordinal - start_or_end_ordinal) AS "concurrent_users"
FROM C2
WHERE TYPE = 1
GROUP BY "date"
ORDER BY "date"
