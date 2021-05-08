WITH C1 AS
(
  SELECT
    start_time AS tss,
    +1 AS TYPE,
    ROW_NUMBER() OVER(ORDER BY start_time) AS start_ordinal,
    name,
    internal_meeting_id,
    end_time AS tse
  FROM meetings WHERE is_breakout = false AND test_meeting = false AND institution_name = 'Mackenzie' AND TO_CHAR(TO_TIMESTAMP(start_time / 1000)::date, 'YYYY-MM') = '2021-04'

  UNION ALL

  SELECT
    end_time,
    -1,
    NULL,
    NULL,
    NULL,
    NULL
  FROM meetings WHERE is_breakout = false AND test_meeting = false AND  institution_name = 'Mackenzie' AND TO_CHAR(TO_TIMESTAMP(start_time / 1000)::date, 'YYYY-MM') = '2021-04'
),
C2 AS
(
  SELECT
    *,
    ROW_NUMBER() OVER(  ORDER BY tss, TYPE ) AS start_or_end_ordinal
  FROM C1
)
SELECT
  TO_CHAR(TO_TIMESTAMP(tss / 1000)::timestamp at time zone 'utc' at time zone 'america/sao_paulo', 'YYYY-MM-DD HH24:MI:SS') AS "start",
  TO_CHAR(TO_TIMESTAMP(tse / 1000)::timestamp at time zone 'utc' at time zone 'america/sao_paulo', 'YYYY-MM-DD HH24:MI:SS') AS "end",
  TO_TIMESTAMP(tse / 1000)::timestamp - TO_TIMESTAMP(tss / 1000)::timestamp AS "duration",
  name,
  internal_meeting_id,
  (2 * start_ordinal - start_or_end_ordinal) AS "concurrent_meetings"
FROM C2
WHERE TYPE = 1
