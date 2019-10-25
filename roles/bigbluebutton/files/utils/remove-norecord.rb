#!/usr/bin/ruby
# encoding: UTF-8

yesterday = Time.now - (60 * 60 * 24)
Dir.glob("/var/bigbluebutton/recording/status/archived/*.norecord").each do |norecorded|
  match = /^(\w+-\d+)\.norecord$/.match File.basename(norecorded)
  next if match.nil? || File.mtime(norecorded) > yesterday
  record_id = match[1]

  puts `bbb-record --delete #{record_id}`
end
