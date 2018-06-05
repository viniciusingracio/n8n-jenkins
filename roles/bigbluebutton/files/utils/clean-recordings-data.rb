#!/usr/bin/ruby
# encoding: UTF-8

require 'fileutils'

Dir.glob("/var/bigbluebutton/recording/status/published/*.done").each do |published|
  match = /^(\w+-\d+)-\w+\.done$/.match File.basename(published)
  next if match.nil?
  record_id = match[1]

  FileUtils.rm_rf "/var/bigbluebutton/#{record_id}", :verbose => true
  FileUtils.rm_rf "/usr/share/red5/webapps/video/streams/#{record_id}", :verbose => true
  FileUtils.rm_rf "/usr/share/red5/webapps/screenshare/streams/#{record_id}", :verbose => true
  FileUtils.rm_rf "/var/freeswitch/meetings/#{record_id}-*.wav", :verbose => true
end
