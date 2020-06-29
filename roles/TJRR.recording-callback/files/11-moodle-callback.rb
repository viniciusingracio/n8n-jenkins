#!/usr/bin/ruby

# install dependencies with:
# sudo apt-get install libmysqlclient-dev
# sudo bundle install
# mysql2

require File.expand_path('../../../lib/recordandplayback', __FILE__)
require 'mysql2'
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

metadata_xml = "/var/bigbluebutton/published/presentation/#{record_id}/metadata.xml"
if ! File.exists? metadata_xml
  BigBlueButton.logger.error "Cannot find a metadata.xml for the recording #{record_id}"
  exit 0
end

props = YAML::load(File.open(File.expand_path('../11-moodle-callback.yml', __FILE__)))
callback_uri = props['callback_uri']

doc = Nokogiri::XML(File.open(metadata_xml)) { |x| x.noblanks }
xml_node = doc.at_xpath("/recording/meeting/@externalId")
if xml_node.nil?
  BigBlueButton.logger.error "Cannot find the meetingId for #{record_id}"
  exit 0
end
meeting_id = xml_node.text

begin
  uri = URI("#{callback_uri}?meetingId=#{meeting_id}")
  status_response = Net::HTTP.get_response(uri)
  if status_response.kind_of? Net::HTTPSuccess
    BigBlueButton.logger.info "HTTP callback to #{uri.to_s} succeeded"
  else
    BigBlueButton.logger.error "HTTP callback to #{uri.to_s} failed with #{status_response.code} #{status_response.message}"
  end
rescue => e
  BigBlueButton.logger.info("Rescued")
  BigBlueButton.logger.info(e.to_s)
end
