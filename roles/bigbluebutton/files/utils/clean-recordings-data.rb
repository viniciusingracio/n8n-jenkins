#!/usr/bin/ruby
# encoding: UTF-8

require 'fileutils'

Dir.glob("/var/bigbluebutton/recording/status/published/*.done").each do |published|
  match = /^(\w+-\d+)-\w+\.done$/.match File.basename(published)
  next if match.nil?
  record_id = match[1]

  FileUtils.rm_rf "/var/bigbluebutton/#{record_id}"
  FileUtils.rm_rf "/usr/share/red5/webapps/video/streams/#{record_id}"
  FileUtils.rm_rf "/usr/share/red5/webapps/screenshare/streams/#{record_id}"
  FileUtils.rm_rf "/var/kurento/recordings/#{record_id}"
  FileUtils.rm_rf "/var/kurento/screenshare/#{record_id}"
  Dir.glob("/var/freeswitch/meetings/#{record_id}-*.opus").each { |file| FileUtils.rm_rf file }
end
