SELECT
  institutions.name AS "institution",
  recordings.internal_meeting_id AS "record_id",
  TO_CHAR(TO_TIMESTAMP(recordings.start_time / 1000)::timestamp, 'YYYY-MM-DD HH24:MI:SS') AS "recorded_at",
  recordings.size
FROM recordings
LEFT JOIN meetings_events
  ON meeting_event_id = meetings_events.id
LEFT JOIN institutions
  ON institutions.guid = meetings_events.institution_guid
WHERE ( status = 'published' OR status = 'unpublished' ) AND institutions.name = 'DataEduc' AND TO_TIMESTAMP(CAST(recordings.start_time/1000 AS bigint))::date <= NOW() - INTERVAL '180 DAYS'
ORDER BY "recorded_at"
