#!/usr/bin/ruby
# encoding: UTF-8

require 'trollop'
require 'date'
require 'fileutils'

opts = Trollop::options do
  opt :filename, "Modified filename of the track", :type => String
end

filename = opts[:filename]

if ! File.exists? filename
  puts "[INFO] File #{filename} doesn't exist"
  exit 0
end

match = /^(\w+-\d+)-\d+-track.txt$/.match File.basename(filename)
if match.nil?
  puts "[WARN] Couldn't parse properly the caption track filename #{filename}"
  exit 1
end
record_id = match[1]

target_filename = "/var/bigbluebutton/published/presentation/#{record_id}/caption_pt_BR.vtt"
if File.exists? target_filename
  if FileUtils.identical? filename, target_filename
    puts "[INFO] Track for #{record_id} is identical"
    exit 0
  end
  datetime = DateTime.parse(File.mtime(target_filename).to_s).strftime("%Y-%m-%d.%H%M%S")
  FileUtils.cp target_filename, "#{target_filename}.#{datetime}"
end

FileUtils.cp filename, target_filename

puts "[INFO] Track for #{record_id} updated"
