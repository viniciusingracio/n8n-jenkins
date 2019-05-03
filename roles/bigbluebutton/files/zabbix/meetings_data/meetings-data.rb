#!/usr/bin/ruby

require 'rubygems'
require 'find'
require 'pp'
require 'date'
require 'json'
require 'tzinfo'
require 'trollop'
require 'nokogiri'

def format_date_time(d)
  timezone = TZInfo::Timezone.get($tz)
  local_date = timezone.utc_to_local(d)
  local_date.strftime("%d/%m/%Y %H:%M:%S")
end

def record_id_to_timestamp(r)
  r.split("-")[1].to_i / 1000
end

def get_dirs(record_id)
  output = Dir.glob("/var/bigbluebutton/published/*/#{record_id}/**/*")
  return output if ! output.empty?

  output = Dir.glob("/var/bigbluebutton/recording/raw/#{record_id}/**/*")
  return output if ! output.empty?

  output = []
  # presentations
  output += Dir.glob("/var/bigbluebutton/#{record_id}/**/*")
  # webcam streams in red5
  output += Dir.glob("/usr/share/red5/webapps/video/streams/#{record_id}/**/*")
  # screenshare streams in red5
  output += Dir.glob("/usr/share/red5/webapps/screenshare/streams/#{record_id}/**/*")
  # desktop sharing streams in red5
  output += Dir.glob("/var/bigbluebutton/deskshare/#{record_id}-*.flv")
  # FreeSWITCH wav recordings
  output += Dir.glob("/var/freeswitch/meetings/#{record_id}-*.wav")
  # webcam streams in kurento
  output += Dir.glob("/var/kurento/recordings/#{record_id}/**/*")
  # screenshare streams in kurento
  output += Dir.glob("/var/kurento/screenshare/#{record_id}/**/*")
  output
end

def get_size(record_id)
  size = 0
  get_dirs(record_id).each { |f| size += File.size(f) if File.file?(f) }
  size
end

def new_record()
  {
    "record_id" => nil,
    "meeting_name" => nil,
    "start_meeting" => nil,
    "end_meeting" => nil,
    "end_sanity" => nil,
    "end_process" => nil,
    "end_publish" => nil,
    "record" => false,
    "status" => nil,
    "queued" => nil
  }
end

def add_info(m, recordings, symbol, date, has_data)
  return if ($now - date).to_i > $retrieve_time_limit
  if symbol == "restart_server"
    recordings.values.select{ |r| ! r["start_meeting"].nil? and r["end_meeting"].nil? }.each do |r|
      r["end_meeting"] = date
      r["end_meeting_event"] = "server_restart"
      r["end_meeting_reason"] = "bbb-web restarted"
    end
  elsif has_data
    info = JSON.parse(m["data"])
    record_id = info["meetingId"]
    recordings[record_id] = new_record if ! recordings.has_key?(record_id)
    recordings[record_id]["record_id"] = record_id
    if info["event"] == "meeting_started"
      recordings[record_id]["meeting_name"] = info["name"]
      recordings[record_id]["record"] = info["record"]
    end
    if symbol == "end_meeting" && ! recordings[record_id].has_key?("end_meeting_event")
      recordings[record_id]["end_meeting_event"] = info["event"]
      recordings[record_id]["end_meeting_reason"] = info["description"]
    end
    recordings[record_id][symbol] = date
  else
    record_id = m["record_id"]
    recordings[record_id] = new_record if ! recordings.has_key?(record_id)
    recordings[record_id]["record_id"] = record_id
    recordings[record_id][symbol] = date
  end
end

def assign_next(line, recordings, symbol, re, date_format)
  if (m = re.match line)
    date = DateTime.strptime(m[:date].to_s, date_format)
    add_info(m, recordings, symbol, date, m.names.include?("data"))
    true
  else
    false
  end
end

recordings = {}
$now = DateTime.now
$retrieve_time_limit = 7

Dir.glob("/var/bigbluebutton/recording/status/sanity/*.done").each do |file|
  record_id = File.basename(file, '.done')
  date = DateTime.parse(File.mtime(file).to_s)
  add_info({ "record_id" => record_id }, recordings, "queued", date, false)
end

date_format = "%Y-%m-%dT%H:%M:%S.%L%:z"
`ls -tr1 /var/log/bigbluebutton/bbb-web.log* | tail -n #{$retrieve_time_limit} | xargs -I{} zgrep 'Meeting started\\|Removing expired meeting\\|Meeting ended\\|Removing un-joined meeting\\|Meeting destroyed\\|Starting Meeting Service' {}`.split("\n").each do |line|
  next if assign_next(line, recordings, "start_meeting", /(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+[^ ]*).*Meeting started: data=(?<data>.*)/i, date_format)
  next if assign_next(line, recordings, "end_meeting", /(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+[^ ]*).*(Meeting ended|Removing expired meeting|Removing un-joined meeting|Meeting destroyed): data=(?<data>.*)/i, date_format)
  next if assign_next(line, recordings, "restart_server", /(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+[^ ]*).*Starting Meeting Service.$/i, date_format)
end

date_format = "%Y-%m-%dT%H:%M:%S.%L"
if ! Dir.glob("/var/log/bigbluebutton/bbb-rap-worker.log*").empty?
  `ls -tr1 /var/log/bigbluebutton/bbb-rap-worker.log* | tail -n #{$retrieve_time_limit} | xargs -I{} zgrep 'Successfully sanity checked\\|Successfully archived\\|Process format.*succeeded\\|Publish format.*succeeded' {}`.split("\n").each do |line|
    next if assign_next(line, recordings, "end_sanity", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Successfully sanity checked (?<record_id>\w+-\d+)/i, date_format)
    next if assign_next(line, recordings, "end_archive", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Successfully archived (?<record_id>\w+-\d+)/i, date_format)
    next if assign_next(line, recordings, "end_process", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Process format (?<format>[^ ]*) succeeded for (?<record_id>\w+-\d+)/i, date_format)
    next if assign_next(line, recordings, "end_publish", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Publish format (?<format>[^ ]*) succeeded for (?<record_id>\w+-\d+)/i, date_format)
  end
end

if ! Dir.glob("/var/log/bigbluebutton/archive-*.log").empty?
  `ls -tr1 /var/log/bigbluebutton/archive-*.log | xargs -I{} zgrep "There's no recording marks for" {}`.split("\n").each do |line|
    next if assign_next(line, recordings, "end_archive_no_segment", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*There's no recording marks for (?<record_id>\w+-\d+)/i, date_format)
  end
end

recordings.each do |record_id, info|
  if ! info["end_publish"].nil?
    info["status"] = "processed"
  elsif File.exists?("/var/bigbluebutton/recording/status/published/#{record_id}-presentation.done")
    info["end_publish"] = DateTime.parse(File.mtime("/var/bigbluebutton/recording/status/published/#{record_id}-presentation.done").to_s)
    info["status"] = "processed"
  elsif ! info["queued"].nil?
    if `find /var/bigbluebutton/recording/status -name "*#{record_id}*.fail" | wc -l`.strip.to_i > 0
      info["status"] = "failed"
    else
      info["status"] = "queued"
    end
  elsif ! info["end_archive_no_segment"].nil?
    info["status"] = "no recorded segment"
    info["end_archive"] = info["end_archive_no_segment"]
  elsif ! info["start_meeting"].nil? and info["end_meeting"].nil?
    info["status"] = "running"
  elsif ( ! info["start_meeting"].nil? and ! info["record"] ) or info["end_meeting_reason"] == "Meeting has not been joined."
    info["status"] = "not recorded"
  elsif info["end_process"].nil?
    info["status"] = "processing"
  elsif info["end_meeting_event"] == "server_restart"
    info["status"] = "server restarted"
  elsif `find /var/bigbluebutton/recording/status -name "*#{record_id}*" | wc -l`.strip.to_i == 0
    info["status"] = "deleted"
  elsif ! info["end_sanity"].nil?
    info["status"] = "processing"
  elsif File.exists?("/var/bigbluebutton/recording/status/archived/#{record_id}.norecord")
    info["status"] = "no recorded segment"
  elsif ! info["end_archive"].nil? && ! File.exists?("/var/bigbluebutton/recording/status/archived/#{record_id}.done")
    info["status"] = "no recorded segment removed"
  else
    info["status"] = "ended"
  end
end

class Array
  def average
    inject(&:+) / size
  end
end

opts = Trollop::options do
  opt :tz, "Timezone, check https://en.wikipedia.org/wiki/List_of_tz_database_time_zones", :default => "America/Sao_Paulo"
  opt :disable_size, "Do not try to figure out recording size", :default => false
  opt :time_limit, "Amount of time in minutes to retrieve data", :default => 60
end

$tz = opts[:tz]
$disable_size = opts[:disable_size]
time_limit = opts[:time_limit].to_i
recordings = recordings.values

# puts recordings.to_json.gsub("},", "},\n ")

filtered = recordings.select{ |e| ! e["end_publish"].nil? && ! e["end_sanity"].nil? }.map{ |e| ((e["end_publish"] - e["end_sanity"]) * 24 * 60).to_i }
if ! filtered.empty?
  m = filtered.average
  recordings.select{ |e| e["end_publish"].nil? && ! e["end_sanity"].nil? }.each { |e| e["end_publish"] = e["end_sanity"] + m / (24 * 60).to_f }
end

recordings.reject! do |e|
  ( e["status"] == "processed" && (($now - e["end_publish"]) * 24 * 60).to_i > time_limit ) || \
  ( ["not recorded", "no recorded segment", "server restarted", "deleted"].include?(e["status"]) && (($now - e["end_meeting"]) * 24 * 60).to_i > time_limit ) || \
  ( e["status"] == "no recorded segment removed" && (($now - e["end_archive"]) * 24 * 60).to_i > time_limit )
end
recordings.each do |info|
  next if ! info["meeting_name"].nil?
  events_xml_path = "/var/bigbluebutton/recording/raw/#{info["record_id"]}/events.xml"
  next if ! File.exists?(events_xml_path)
  events_xml = Nokogiri::XML(File.open(events_xml_path))
  info["meeting_name"] = events_xml.at_xpath('/recording/metadata')['meetingName']
end
recordings.sort! { |a,b| record_id_to_timestamp(b["record_id"]) <=> record_id_to_timestamp(a["record_id"]) }
recordings.map! do |info|
  result =   {
    "name" => info["meeting_name"],
    "id" => info["record_id"],
    "status" => info["status"]
  }
  result["begin"] = format_date_time(info["start_meeting"]) if ! info["start_meeting"].nil?
  result["end"] = format_date_time(info["end_meeting"]) if ! info["end_meeting"].nil?
  result["queue"] = format_date_time(info["queued"]) if ! info["queued"].nil?
  result["size"] = (get_size(info["record_id"]).to_f / 1024 / 1024).round(1) if ! $disable_size
  result["publish"] = format_date_time(info["end_publish"]) if ! info["end_publish"].nil?
  result
end

puts recordings.to_json.gsub("},", "},\n ")

