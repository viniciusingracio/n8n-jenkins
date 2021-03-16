#!/usr/bin/ruby
# encoding: UTF-8

# delay in two hours to remove the data
little_ago = Time.now - (60 * 60 * 2)
Dir.glob("/var/bigbluebutton/recording/status/archived/*.norecord").each do |norecorded|
  match = /^(\w+-\d+)\.norecord$/.match File.basename(norecorded)
  next if match.nil? || File.mtime(norecorded) > little_ago
  record_id = match[1]

  puts `bbb-record --delete #{record_id}`
end
