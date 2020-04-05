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
  d.strftime("%d/%m/%Y %H:%M:%S")
end

def record_id_to_timestamp(r)
    r.split("-")[1].to_i / 1000
end

def assign_next(line, recordings, symbol, re, date_format)
  if (m = re.match line)
    date = DateTime.strptime(m[:date].to_s, date_format)
    record_id = m["record_id"]
    symbol += "_#{m[:format]}" if m.names.include? "format"
    recordings[record_id] = { "record_id" => record_id } if ! recordings.has_key?(record_id)
    recordings[record_id][symbol] = format_date_time(date)
    true
  else
    false
  end
end

recordings = {}

date_format = "%Y-%m-%dT%H:%M:%S.%L"

`find /tmp/recording-logs/ -name "bbb-rap-worker.log*" | xargs -I{} zgrep 'Successfully sanity checked\\|Successfully archived\\|Process format.*succeeded\\|Publish format.*succeeded\\|Executing: ruby process\\|Executing: ruby publish' {} | sort`.split("\n").each do |line|
  next if assign_next(line, recordings, "end_sanity", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Successfully sanity checked (?<record_id>\w+-\d+)/i, date_format)
  next if assign_next(line, recordings, "end_archive", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Successfully archived (?<record_id>\w+-\d+)/i, date_format)
  next if assign_next(line, recordings, "end_process", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Process format (?<format>[^ ]*) succeeded for (?<record_id>\w+-\d+)/i, date_format)
  next if assign_next(line, recordings, "end_publish", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Publish format (?<format>[^ ]*) succeeded for (?<record_id>\w+-\d+)/i, date_format)
  next if assign_next(line, recordings, "begin_process", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Executing: ruby process\/(?<format>[^ ]*).rb -m (?<record_id>\w+-\d+)/i, date_format)
  next if assign_next(line, recordings, "begin_publish", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Executing: ruby publish\/(?<format>[^ ]*).rb -m (?<record_id>\w+-\d+)/i, date_format)
end

# `find /tmp/recording-logs/ -name "mconf-presentation-recorder-worker.*" | xargs -I{} zgrep 'Recording of meeting ' {} | sort`.split("\n").each do |line|
#   next if assign_next(line, recordings, "begin_presentation_recorder", /\[(?<date>\d+-\d+-\d+.\d+:\d+:\d+\.\d+).*Recording of meeting (?<record_id>\w+-\d+)/i, date_format)
# end

column_names = recordings.values.first.keys
s = CSV.generate do |csv|
  csv << column_names
  recordings.values.sort{ |a,b| record_id_to_timestamp(a["record_id"]) <=> record_id_to_timestamp(b["record_id"]) }.each do |record|
    csv << record.values
  end
end

puts s
