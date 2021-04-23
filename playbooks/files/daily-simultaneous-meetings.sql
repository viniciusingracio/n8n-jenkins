WITH C1 AS
(
  SELECT
    start_time AS tss,
    +1 AS TYPE,
    ROW_NUMBER() OVER(ORDER BY start_time) AS start_ordinal
  FROM meetings WHERE is_breakout = false AND test_meeting = false

  UNION ALL

  SELECT
    end_time,
    -1,
    NULL
  FROM meetings WHERE is_breakout = false AND test_meeting = false
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
  MAX(2 * start_ordinal - start_or_end_ordinal) AS "concurrent_meetings"
FROM C2
WHERE TYPE = 1
GROUP BY "date"
ORDER BY "date"
