#!/usr/bin/ruby
# encoding: UTF-8

# sudo gem install optimist tz

# Example:
# ruby backup-recordings.rb --xpath "/recording/meta/mconflb-institution-name" --value "CAPES" --dry-run

require 'optimist'
require 'nokogiri'
require 'date'
require 'fileutils'
require 'tz'

opts = Optimist::options do
  opt :xpath, "xpath to select recordings", :type => String, :required => true
  opt :value, "value for the xpath to match", :type => String, :required => true
  opt :dry_run, "do not execute anything, just search", :type => :flag, :default => false
end

def timestamp_to_date(ms)
    DateTime.strptime(ms.to_s,'%Q')
end

def format_date_time(d, timezone_s = "America/Sao_Paulo")
    timezone = TZInfo::Timezone.get(timezone_s)
    local_date = timezone.utc_to_local(d)
    local_date.strftime("%Y-%m-%d %H:%M:%S")
end

def record_id_to_timestamp(r)
    r.split("-")[1].to_i
end

def get_size(dir_name)
  size = 0
  if FileTest.directory?(dir_name)
    Find.find(dir_name) { |f| size += File.size(f) }
  else
    size = File.size(dir_name)
  end
  size
end

size = 0
num = 0

files = `find /var/bigbluebutton/published/presentation_video/ /var/bigbluebutton/unpublished/presentation_video/ /var/bigbluebutton/deleted/presentation_video/ -name metadata.xml`.split("\n")
files.each do |filename|
    doc = Nokogiri::XML(File.open(filename), nil, "UTF-8") { |x| x.noblanks }

    xml_node = doc.at_xpath(opts[:xpath])
    next if xml_node.nil? || xml_node.content != opts[:value]

    xml_node = doc.at_xpath("/recording/id")
    record_id = xml_node.content

    date = timestamp_to_date(record_id_to_timestamp(record_id))
    next if date.year != 2018

    dir = File.dirname(filename)
    video = Dir.glob(["#{dir}/*.mp4", "#{dir}/*.webm"]).first
    if video
      xml_node = doc.at_xpath("/recording/meta/meetingName")
      meeting_name = xml_node.content

      new_filename = "#{meeting_name} #{format_date_time(date)}#{File.extname(File.basename(video))}".gsub("/", "_").encode('ASCII', invalid: :replace, undef: :replace, replace: "_")
      puts "Copying #{video} to #{new_filename}"
      FileUtils.cp video, new_filename if ! opts[:dry_run]

      size += get_size(video)
      num += 1
    else
      puts "No video file found for #{record_id}"
    end
end

puts "Total number of recordings: #{num}"
puts "Total size: #{size/(1024*1024*1024)}GB"
