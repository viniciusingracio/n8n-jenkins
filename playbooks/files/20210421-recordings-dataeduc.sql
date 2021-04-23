SELECT
  TO_CHAR(meetings_events.create_date::timestamp at time zone 'utc' at time zone 'america/sao_paulo', 'YYYY-MM-DD HH24:MI:SS') as "date",
  CONCAT(recordings.metadata->>'originservername', recordings.metadata->>'bbb-origin-server-name') AS "origin",
  CONCAT(CONCAT(recordings.metadata->>'context', recordings.metadata->>'bbb-context'), recordings.metadata->>'bbb-context-title') AS "course",
  meetings_events.shared_secret_name,
  recordings.record_id,
  recordings.name
FROM recordings
LEFT JOIN meetings_events
  ON recordings.meeting_event_id = meetings_events.id
LEFT JOIN institutions
  ON institutions.guid = meetings_events.institution_guid
WHERE playback::text <> '[]' AND status = 'published' AND institutions.name = 'DataEduc'
ORDER BY "date"
