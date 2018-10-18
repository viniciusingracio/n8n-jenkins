#!/usr/bin/ruby
# encoding: UTF-8

Dir.glob( [ "/var/bigbluebutton/recording/status/archived/*.norecord", "/var/bigbluebutton/recording/status/ended/*.norecord" ] ).each do |norecorded|
  match = /^(\w+-\d+)\.norecord$/.match File.basename(norecorded)
  next if match.nil?
  record_id = match[1]

  puts `bbb-record --delete #{record_id}`
end
