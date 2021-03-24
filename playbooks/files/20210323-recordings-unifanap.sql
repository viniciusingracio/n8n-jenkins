SELECT
  TO_CHAR(meetings_events.create_date::timestamp at time zone 'utc' at time zone 'america/sao_paulo', 'YYYY-MM-DD HH24:MI:SS') as "date",
  CONCAT(CONCAT(recordings.metadata->>'context', recordings.metadata->>'bbb-context'), recordings.metadata->>'bbb-context-title') AS "course",
  recordings.name,
  TO_CHAR((playback_obj->>'duration')::interval / 1000, 'HH24:MI:SS') AS "duration"
FROM recordings CROSS JOIN json_array_elements(recordings.playback) playback_obj
LEFT JOIN meetings_events
  ON recordings.meeting_event_id = meetings_events.id
LEFT JOIN institutions
  ON institutions.guid = meetings_events.institution_guid
WHERE playback::text <> '[]' AND status = 'published' AND playback_obj->>'format' = 'presentation' AND institutions.name = 'UniFANAP'
ORDER BY "date"
