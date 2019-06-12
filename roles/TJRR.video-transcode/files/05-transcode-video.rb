#!/usr/bin/ruby

require File.expand_path('../../../lib/recordandplayback', __FILE__)
require 'trollop'
require 'date'
require 'net/http'

logger = Logger.new("/var/log/bigbluebutton/post_publish.log", 'weekly' )
logger.level = Logger::INFO
BigBlueButton.logger = logger

opts = Trollop::options do
  opt :meeting_id, "Meeting id to archive", :type => String
end
record_id = opts[:meeting_id]
published_dir = "/var/bigbluebutton/published/presentation/#{record_id}"
metadata_xml = "#{published_dir}/metadata.xml"
exit 0 if ! File.exists? metadata_xml
video_file = "#{published_dir}/video/webcams.mp4"
exit 0 if ! File.exists? video_file

props = YAML::load(File.open(File.expand_path('../05-transcode-video.yml', __FILE__)))

metadata = Nokogiri::XML(File.open(metadata_xml)) { |x| x.noblanks }

props['matcher'].each do |item|
  node = metadata.at_xpath(item['xpath'])

  if ! node.nil? && node.text == item['value']
    new_video_file = "#{published_dir}/video/new.mp4"
    command = "ffmpeg -i #{video_file} -c:v libx264 -x264-params 'nal-hrd=cbr' -b:v 100k -minrate 100k -maxrate 100k -bufsize 200k -vf scale=320:240 -c:a libfdk_aac -b:a 48k #{new_video_file}"
    result = BigBlueButton.execute command, false
    if result.success?
      FileUtils.mv new_video_file, video_file
    else
      FileUtils.rm_f new_video_file
    end
    exit 0
  end
end
