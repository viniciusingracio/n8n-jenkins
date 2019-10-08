# encoding: UTF-8

# ruby recordings-data.rb | sudo tee /var/www/bigbluebutton-default/tmp/recordings-$(date +"%Y%m%d").csv

require 'nokogiri'
require 'find'
require 'pp'
require 'csv'
require 'date'

def get_dir_size(dir_name)
  size = 0
  if FileTest.directory?(dir_name)
    Find.find(dir_name) { |f| size += File.size(f) }
  end
  size
end

def ms_to_strtime(ms)
  t = Time.at(ms / 1000, (ms % 1000) * 1000)
  t.getutc.strftime("%H:%M:%S.%L")
end

def format_date_time(d)
  d.strftime("%m/%d/%Y %H:%M:%S")
end

def record_id_to_timestamp(r)
    r.split("-")[1].to_i / 1000
end

def new_record()
  {
    "record_id" => nil,
    "meeting_name" => nil,
    "start_time" => 0,
    "end_time" => 0,
    "meeting_minutes_raw" => 0,
    "raw_size" => 0,
    "mb_per_minute_raw" => 0,
    "state" => nil,
    "playback_duration" => 0,
    "meeting_minutes_pb" => 0,
    "mb_per_minute_pb" => 0,
    "presentation_available" => false,
    "presentation_video_available" => false,
    "presentation_export_available" => false,
    "playback_size" => 0,
    "presentation_size" => 0,
    "presentation_video_size" => 0,
    "presentation_export_size" => 0,
    "start_fetch" => nil,
    "end_fetch" => nil,
    "start_sanity" => nil,
    "end_sanity" => nil,
    "start_process_presentation" => nil,
    "end_process_presentation" => nil,
    "start_publish_presentation" => nil,
    "end_publish_presentation" => nil,
    "start_process_presentation_export" => nil,
    "end_process_presentation_export" => nil,
    "start_publish_presentation_export" => nil,
    "end_publish_presentation_export" => nil,
    "start_process_presentation_video" => nil,
    "end_process_presentation_video" => nil,
    "start_publish_presentation_video" => nil,
    "end_publish_presentation_video" => nil,
    "context" => nil
  }
end

def assign_next(line, recordings, symbol, re)
  puts line
  if (m = re.match line)
    d = format_date_time(DateTime.strptime(m[:date].to_s, '%Y-%m-%dT%H:%M:%S.%L'))
    record_id = m[:record_id].to_s
    if ! recordings.has_key?(record_id)
      # puts "For some reason, record_id #{m[:record_id]} found by regexp #{re.to_s} was not found"
    elsif recordings[record_id][symbol].nil? || recordings[record_id][symbol] < d
      recordings[record_id][symbol] = d
    end
    true
  else
    false
  end
end

recordings = {}
Dir.glob( [ "/var/bigbluebutton/published/*/*",
            "/var/bigbluebutton/unpublished/*/*",
            "/var/bigbluebutton/deleted/*/*",
            "/var/bigbluebutton/recording/raw/*" ]).map{ |d| File.basename(d) }.select{ |r| r =~ /\w+-\d+/ }.uniq.each do |record_id|
  record = new_record
  record["record_id"] = record_id

  recording_dir = "/var/bigbluebutton/recording/raw/#{record_id}"
  events_xml_path = "#{recording_dir}/events.xml"
  if File.exists?(events_xml_path)
    match = /(\w+)-(\d+)/.match record_id
    start_time = match[2].to_i

    events_xml = Nokogiri::XML(File.open(events_xml_path))
    first_timestamp = events_xml.xpath("/recording/event").first["timestamp"].to_i
    last_timestamp = events_xml.xpath("/recording/event").last["timestamp"].to_i

    record["meeting_name"] = events_xml.at_xpath('/recording/metadata')['meetingName']
    record["start_time"] = start_time
    record["end_time"] = start_time + last_timestamp - first_timestamp
    record["raw_size"] = get_dir_size(recording_dir).to_f / 1024 / 1024
  end

  [ "presentation", "presentation_export", "presentation_video" ].each do |pres_format|
    [ "published", "unpublished", "deleted" ].each do |pres_status|
      recording_dir = "/var/bigbluebutton/#{pres_status}/#{pres_format}/#{record_id}"
      metadata_xml_path = "#{recording_dir}/metadata.xml"
      next if ! File.exists?(metadata_xml_path)

      metadata_xml = Nokogiri::XML(File.open(metadata_xml_path))
      record["meeting_name"] = metadata_xml.at_xpath('/recording/meta/meetingName').text
      record["state"] = metadata_xml.at_xpath('/recording/state').text
      record["start_time"] = metadata_xml.at_xpath('/recording/start_time').text.to_i if record["start_time"] == 0
      record["end_time"] = metadata_xml.at_xpath('/recording/end_time').text.to_i if record["end_time"] == 0
      if ! (duration_node = metadata_xml.at_xpath('/recording/playback/duration')).nil?
        record["playback_duration"] = duration_node.text.to_i if record["playback_duration"] == 0
      end
      record["#{pres_format}_available"] = true
      record["#{pres_format}_size"] = get_dir_size(recording_dir).to_f / 1024 / 1024
      record["playback_size"] += record["#{pres_format}_size"]

      node = metadata_xml.at_xpath('/recording/meta/bbb-context')
      record["context"] = node.text if ! node.nil?
    end
  end

  if record["start_time"] > 0 && record["end_time"] > 0
    start_time = DateTime.strptime(record["start_time"].to_s,'%Q')
    end_time = DateTime.strptime(record["end_time"].to_s,'%Q')
    record["start_time"] = format_date_time(start_time)
    record["end_time"] = format_date_time(end_time)
    record["meeting_minutes_raw"] = ((end_time - start_time) * 24 * 60).to_i
  end
  record["meeting_minutes_pb"] = (record["playback_duration"].to_f / 1000 / 60).round(2) if record["playback_duration"] != 0
  record["playback_duration"] = ms_to_strtime(record["playback_duration"]) if record["playback_duration"] != 0
  record["mb_per_minute_raw"] = record["raw_size"] / record["meeting_minutes_raw"] if record["raw_size"] > 0
  record["mb_per_minute_pb"] = record["playback_size"] / record["meeting_minutes_pb"] if record["meeting_minutes_pb"] > 0

  recordings[record_id] = record
end

#Dir.glob("/var/log/bigbluebutton/mconf_decrypter.log*").each do |file|
#  File::readlines(file).each do |line|
#    next if assign_next(line, recordings, "start_fetch", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Next recording.* (?<record_id>\w+-\d+)/i)
#    next if assign_next(line, recordings, "end_fetch", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Recording (?<record_id>\w+-\d+) decrypted successfully/i)
#  end
#end

#Dir.glob("/var/log/bigbluebutton/bbb-rap-worker.log*").each do |file|
#  File::readlines(file).each do |line|
#    next if assign_next(line, recordings, "start_sanity", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Executing: ruby sanity\/sanity.rb -m (?<record_id>\w+-\d+)/i)
#    next if assign_next(line, recordings, "end_sanity", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Successfully sanity checked (?<record_id>\w+-\d+)/i)
#    [ "presentation", "presentation_export", "presentation_video" ].each do |pres_format|
#      [ "process", "publish" ].each do |pres_step|
#        break if assign_next(line, recordings, "start_#{pres_step}_#{pres_format}", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Executing: ruby #{pres_step}\/#{pres_format}.rb -m (?<record_id>\w+-\d+)/i)
#        break if assign_next(line, recordings, "end_#{pres_step}_#{pres_format}", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*#{pres_step} format #{pres_format} succeeded for (?<record_id>\w+-\d+)/i)
#      end
#    end
#  end
#end

column_names = recordings.values.first.keys
s = CSV.generate do |csv|
  csv << column_names
  recordings.values.sort{ |a,b| record_id_to_timestamp(a["record_id"]) <=> record_id_to_timestamp(b["record_id"]) }.each do |record|
    csv << record.values
  end
end

puts s
