#!/usr/bin/ruby
# Set encoding to utf-8
# encoding: utf-8

require '../lib/bigbluebutton_s3'
require '../lib/recordandplayback'
require 'bbbevents'
require 'dotenv'
require 'fileutils'
require 'i18n'
require 'logger'
require 'nokogiri'
require 'terminal-table'
require 'yaml'

Dotenv.load(
  File.join(File.dirname(__FILE__), '.env.local'),
  File.join(File.dirname(__FILE__), '.env')
)

METADATA_SHARED_ID_KEY = "mconf-shared-secret-guid"
METADATA_EXTERNAL_ID_KEY = "meetingId"
METADATA_LOCALE_KEY = "mconf-locale"
METADATA_TIMEZONE_KEY = "mconf-timezone"
METADATA_TIMEZONE_OFFSET_KEY = "mconf-timezone-offset"

def fetch_meetings(events_dir, dir)
  BigBlueButton.logger.info("Fetching meetings")
  meetings = []
  begin
    if FileTest.directory?(events_dir) and FileTest.directory?(dir)
      command = "diff --brief #{events_dir} #{dir} | grep 'Only in #{events_dir}' | awk '{print $4}'"
      result = `#{command}`
      if $?.success?
        result = result.split("\n")
        if result.any?
          meetings = result.map { |meeting_id| meeting_id.strip }
        end
      end
    else
      BigBlueButton.logger.warn("Could not find one or both of these directories: #{events_dir} #{dir}")
    end
  rescue Exception => e
    BigBlueButton.logger.error("Failed to compare #{events_dir} to #{dir}: #{e.to_s}")
  end

  meetings
end

def seconds_to_duration(t)
  seconds = t % 60
  minutes = (t / 60) % 60
  hours = t / (60 * 60)
  format("%02d:%02d:%02d", hours, minutes, seconds)
end

def time_to_datetime(t)
  # Convert seconds + microseconds into a fractional number of seconds
  seconds = t.sec + Rational(t.usec, 10**6)

  # Convert a UTC offset measured in minutes to one measured in a
  # fraction of a day.
  offset = Rational(t.utc_offset, 60 * 60 * 24)
  DateTime.new(t.year, t.month, t.day, t.hour, t.min, seconds, offset)
end

def local_date_time(d, timezone_offset)
  time_to_datetime(d).new_offset(timezone_offset)
end

def format_date_time(d, timezone_offset)
  local_date = local_date_time(d, timezone_offset)
  I18n.l(local_date, format: :datetime)
end

def format_time(d, timezone_offset)
  local_date = local_date_time(d, timezone_offset)
  local_date.strftime("%H:%M:%S")
end

def format_activities(recording, target, timezone:, timezone_offset:)
  File.open(target, "w") do |file|
    file.puts I18n.t('session.name', val: recording.metadata[:meeting_name])
    file.puts I18n.t('session.date', val: format_date_time(recording.start.utc, timezone_offset))
    file.puts I18n.t('session.duration', val: seconds_to_duration(recording.duration))

    unless recording.recorded_segments.empty?
      file.puts
      file.puts I18n.t('recorded_segments.title', val: recording.recorded_segments.length)
      recording.recorded_segments.each_with_index do |segment, index|
        file.puts I18n.t('recorded_segments.item', index: index + 1, start: format_time(segment.start.utc, timezone_offset), stop: format_time(segment.stop.utc, timezone_offset), duration: seconds_to_duration(segment.duration))
      end
      # sum!
      file.puts I18n.t('recorded_segments.total', val: seconds_to_duration(recording.recorded_segments.map{ |s| s.duration }.inject(0) { |sum, x| sum + x }))
    end

    unless recording.moderators.empty?
      file.puts
      file.puts I18n.t('moderators')
      recording.moderators.sort_by(&:name).uniq{ |attendee| attendee.name }.each do |attendee|
        file.puts attendee.name
      end
    end

    unless recording.viewers.empty?
      file.puts
      file.puts I18n.t('viewers')
      recording.viewers.sort_by(&:name).uniq{ |attendee| attendee.name }.each do |attendee|
        file.puts attendee.name
      end
    end

    unless recording.attendees.empty?
      file.puts
      file.puts I18n.t('activity.title')
      file.puts Terminal::Table.new(
        :headings => [ I18n.t('activity.name'), I18n.t('activity.chat'), I18n.t('activity.talk'), I18n.t('activity.poll_votes'), I18n.t('activity.raisehand'), I18n.t('activity.talk_time'), I18n.t('activity.join'), I18n.t('activity.leave'), I18n.t('activity.duration') ],
        :rows => recording.attendees.sort_by(&:name).map{ |entry| [
          entry.name,
          entry.engagement[:chats],
          entry.engagement[:talks],
          entry.engagement[:poll_votes],
          entry.engagement[:raisehand],
          seconds_to_duration(entry.engagement[:talk_time]),
          format_time(entry.joined.utc, timezone_offset),
          format_time(entry.left.utc, timezone_offset),
          seconds_to_duration(entry.duration),
        ] } )
    end

    unless recording.polls.empty?
      file.puts
      file.puts I18n.t('polls.title')
      recording.polls.each_with_index do |poll, index|
        file.puts I18n.t('polls.item', index: index + 1, start: format_time(poll.start.utc, timezone_offset), votes: poll.votes.length)
        votes = []
        if poll.votes.empty?
          poll.options.each_with_index do |option, idx|
            file.puts "  #{option}"
          end
        else
          poll.options.each do |option|
            count = poll.votes.select{ |user_id, vote| vote == option}.length
            votes << {
              :count => count,
              :perc => ( ( count / poll.votes.length.to_f ) * 100 ).round(1)
            }
          end
          # sum!
          round_perc = votes.map{ |v| v[:perc].round(0) }.inject(0) { |sum, x| sum + x } == 100
          poll.options.each_with_index do |option, idx|
            file.puts "  #{option}: #{votes[idx][:count]} (#{round_perc ? votes[idx][:perc].round(0) : votes[idx][:perc]}%)"
          end
        end
      end
      file.puts Terminal::Table.new(
        :headings => [ I18n.t('polls.name') ] + (1..recording.polls.length).map { |i| "\# #{i}" },
        :rows => recording.attendees.sort_by(&:name).map{ |entry| [ entry.name ] + recording.polls.map { |poll| poll.votes[entry.id] || "-" }
        } )
    end

    file.puts
    file.puts I18n.t('timezone', val: timezone)
  end
end

def fetch_activities(events, target_dir, timezone:, timezone_offset:)
  BigBlueButton.logger.info("Fetching users activities")

  activities = {
    :uri => "#{target_dir}/activities.txt",
    :uri_raw => "#{target_dir}/activities.json",
    :name => "Users Activities"
  }

  data = BBBEvents.parse(events)

  File.write(activities[:uri_raw], data.to_json)
  format_activities(data, activities[:uri], timezone: timezone, timezone_offset: timezone_offset)

  activities
end

def fetch_chat(events, target_dir)
  BigBlueButton.logger.info("Fetching chat")

  chat = {
    :uri => "#{target_dir}/chat.txt",
    :name => "Public Chat"
  }

  file = File.new(chat[:uri], "w")
  events.xpath("//event[@eventname='PublicChatEvent']").each do |chat_event|
    sender = chat_event.xpath("sender").text
    message = chat_event.xpath("message").text
    file.puts("#{sender}: #{message}")
  end
  file.close

  chat
end

def fetch_notes(meeting_id, events, target_dir, endpoint:, api_key:)
  BigBlueButton.logger.info("Fetching notes")
  id = BigBlueButton.get_notes_id(meeting_id, api_key)

  notes = {
    :uri => "#{target_dir}/notes.txt",
    :name => "Shared Notes"
  }

  BigBlueButton.try_download("#{endpoint}/#{id}/export/txt", notes[:uri])

  notes
end

def fetch_presentations(meeting_id, events, target_dir)
  BigBlueButton.logger.info("Fetching presentations")
  presentations_dir = "/var/bigbluebutton/#{meeting_id}/#{meeting_id}"
  presentations_data_dir = "#{target_dir}/presentations"
  presentations = []
  events.xpath("//event[@eventname='ConversionCompletedEvent']").each do |presentation_event|
    FileUtils.mkdir_p(presentations_data_dir) if not FileTest.directory?(presentations_data_dir)
    id = presentation_event.xpath("presentationName").text
    filename = presentation_event.xpath("originalFilename").text
    extension = filename.split('.').last
    presentation_file = "#{presentations_dir}/#{id}/#{id}.#{extension}"
    if File.exist?(presentation_file)
      FileUtils.cp(presentation_file, presentations_data_dir)
      presentations << {
        :uri => "#{presentations_data_dir}/#{id}.#{extension}",
        :name => filename
      }
    else
      BigBlueButton.logger.warn("Could not find #{presentation_file}")
    end
  end

  presentations
end

def publish_to_s3(meeting_id, props, target_dir, meeting_shared_id)
  success = true
  props_s3 = props['s3']
  if props_s3['enabled']
    BigBlueButton.logger.info("Publishing data for #{meeting_id}")
    bucket_name = props_s3['bucket_name']
    region = props_s3['region'] || ENV['BBB_S3_REGION']
    endpoint = props_s3['endpoint'] || ENV['BBB_S3_ENDPOINT']
    key = props_s3['key'] || ENV['BBB_S3_KEY']
    secret = props_s3['secret'] || ENV['BBB_S3_SECRET']

    publisher = BigBlueButtonS3::Publisher.new(key, secret, region, endpoint)
    remote_prefix = "#{meeting_shared_id}"
    dir = "#{target_dir}/#{meeting_shared_id}"
    success = publisher.upload_dir(dir, remote_prefix, bucket_name)
    BigBlueButton.logger.info("Data published? #{success}")
  end

  success
end

begin
  I18n.enforce_available_locales = true
  I18n.available_locales = Dir['mconf-data-locale/*.yml'].map{ |l| File.basename(l, '.yml').to_sym }
  I18n.load_path = Dir['mconf-data-locale/*.yml']
  I18n.backend.load_translations

  bbb_props = YAML::load(File.open('bigbluebutton.yml'))
  events_dir = bbb_props['events_dir']
  redis_host = bbb_props['redis_host']
  redis_port = bbb_props['redis_port']
  redis_password = bbb_props['redis_password']
  log_dir = bbb_props['log_dir']
  notes_endpoint = bbb_props['notes_endpoint']
  notes_apikey = bbb_props['notes_apikey']

  props = YAML::load(File.open('mconf-data.yml'))
  props_dir = props['dir']
  props_data = props['data']
  default_locale = props['default_locale'].to_sym
  default_timezone = props['default_timezone']
  default_timezone_offset = props['default_timezone_offset']

  BigBlueButton.logger = Logger.new("#{log_dir}/mconf-data.log")
  BigBlueButton.redis_publisher = BigBlueButton::RedisWrapper.new(redis_host, redis_port, redis_password)

  meetings = fetch_meetings(events_dir, props_dir)
  meetings.each do |meeting_id|
    BigBlueButton.logger.info("Collecting data for #{meeting_id}")
    meeting_events_dir = "#{events_dir}/#{meeting_id}"
    meeting_events_xml = "#{meeting_events_dir}/events.xml"
    next unless File.exists?(meeting_events_xml)

    target_dir = "#{props_dir}/#{meeting_id}"
    if not FileTest.directory?(target_dir)
      BigBlueButton.logger.info("Creating directory for #{meeting_id}")
      FileUtils.mkdir_p(target_dir)

      metadata = BigBlueButton::Events.get_meeting_metadata(meeting_events_xml)

      # do not process breakout room
      next if metadata["isBreakout"].to_s == "true"

      meeting_shared_id = "meeting_shared_id"
      if metadata.has_key?(METADATA_SHARED_ID_KEY) and not metadata[METADATA_SHARED_ID_KEY].to_s.empty?
        meeting_shared_id = metadata[METADATA_SHARED_ID_KEY].to_s
      else
        BigBlueButton.logger.info("Missing #{METADATA_SHARED_ID_KEY} metadata for #{meeting_id}")
        next
      end

      meeting_external_id = "meeting_external_id"
      if metadata.has_key?(METADATA_EXTERNAL_ID_KEY) and not metadata[METADATA_EXTERNAL_ID_KEY].to_s.empty?
        meeting_external_id = metadata[METADATA_EXTERNAL_ID_KEY].to_s
      else
        BigBlueButton.logger.info("Missing #{METADATA_EXTERNAL_ID_KEY} metadata for #{meeting_id}")
        next
      end

      locale = if metadata.has_key?(METADATA_LOCALE_KEY)
        metadata[METADATA_LOCALE_KEY].to_sym
      else
        default_locale
      end
      I18n.locale = I18n.available_locales.include?(locale) ? locale : :en

      timezone = default_timezone
      timezone_offset = default_timezone_offset
      if metadata.has_key?(METADATA_TIMEZONE_KEY) and metadata.has_key?(METADATA_TIMEZONE_OFFSET_KEY)
        timezone = metadata[METADATA_TIMEZONE_KEY].to_s
        timezone_offset = metadata[METADATA_TIMEZONE_OFFSET_KEY].to_s
      end

      data_path = "#{target_dir}/#{meeting_shared_id}/#{meeting_external_id}/#{meeting_id}"
      BigBlueButton.logger.info("Creating data path #{data_path}")
      FileUtils.mkdir_p(data_path)

      events = Nokogiri::XML(File.open(meeting_events_xml))
      data = {}
      data[:activities] = fetch_activities(meeting_events_xml, data_path, timezone: timezone, timezone_offset: timezone_offset) if props_data.include? 'activities'
      data[:chat] = fetch_chat(events, data_path) if props_data.include? 'chat'
      data[:notes] = fetch_notes(meeting_id, events, data_path, endpoint: notes_endpoint, api_key: notes_apikey) if props_data.include? 'notes'
      data[:presentations] = fetch_presentations(meeting_id, events, data_path) if props_data.include? 'presentations'

      success = publish_to_s3(meeting_id, props, target_dir, meeting_shared_id)

      BigBlueButton.redis_publisher.put_custom_message("mconf_data", meeting_id, data) if success
    end
  end
rescue Exception => e
  BigBlueButton.logger.error(e.message)
  e.backtrace.each do |traceline|
    BigBlueButton.logger.error(traceline)
  end
end

