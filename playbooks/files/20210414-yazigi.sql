SELECT
  TO_CHAR(TO_TIMESTAMP(join_time / 1000)::timestamp, 'YYYY-MM-DD HH24:MI:SS') AS "date",
  users.name AS "user",
  users.role,
  TO_TIMESTAMP(leave_time / 1000)::timestamp - TO_TIMESTAMP(join_time / 1000)::timestamp AS "duration",
  meetings.metadata->>'bbb-context-title' AS "course",
  meetings.name AS "session"
FROM users JOIN meetings ON users.meeting_id = meetings.id
WHERE is_breakout = false AND test_meeting = false AND integration_origin = 'yazvirtua.brightspace.com' AND institution_name = 'Pearson'
ORDER BY "date" ASC
