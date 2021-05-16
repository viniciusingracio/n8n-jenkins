#!/usr/bin/ruby
# encoding: UTF-8

require '/usr/local/bigbluebutton/core/lib/recordandplayback.rb'
require 'trollop'

opts = Trollop::options do
  opt :meeting_id, "Meeting ID", :type => String, :required => true
  opt :dry_run, "Do not execute anything", :type => :flag, :default => false
  opt :sanity_only, "", :type => :flag, :default => false
  opt :skip_sanity, "", :type => :flag, :default => false
end
meeting_id = opts[:meeting_id]

if ! opts[:dry_run]
  props = YAML::load(File.open('/usr/local/bigbluebutton/core/scripts/bigbluebutton.yml'))
  redis_host = props['redis_host']
  redis_port = props['redis_port']
  redis_password = props['redis_password']
  BigBlueButton.redis_publisher = BigBlueButton::RedisWrapper.new(redis_host, redis_port, redis_password)
end

list = Dir.glob( [ "/var/bigbluebutton/published/*/#{meeting_id}/metadata.xml", "/var/bigbluebutton/unpublished/*/#{meeting_id}/metadata.xml", "/var/bigbluebutton/deleted/*/#{meeting_id}/metadata.xml" ] )
exit 0 if list.empty?

if ! opts[:dry_run] && ! opts[:skip_sanity]
  BigBlueButton.redis_publisher.put_sanity_started(meeting_id)
  BigBlueButton.redis_publisher.put_sanity_ended(meeting_id)
end

exit 0 if opts[:sanity_only]

list.each do |metadata_xml_path|
  match = /\/var\/bigbluebutton\/(?<visibility>\w+)\/(?<format>\w+)\/(?<record_id>\w+-\d+)\/metadata.xml/.match metadata_xml_path
  next if match.nil?
  publish_type = match[:format]
  visibility = match[:visibility]
  BigBlueButton.logger.info "Processing record_id #{meeting_id}, format #{publish_type}, visibility #{visibility}"

  payload = {}
  begin
    doc = Hash.from_xml(File.open(metadata_xml_path))
    playback = doc.dig(:recording, :playback) || {}

    xml_doc = Nokogiri::XML(File.open(metadata_xml_path)) { |x| x.noblanks }
    playback[:extensions][:preview][:images][:image] = [ playback[:extensions][:preview][:images][:image] ] if xml_doc.xpath("/recording/playback/extensions/preview/images/image").size == 1

    payload = {
      "success" => true,
      "step_time" => 0,
      "playback" => playback,
      "metadata" => BigBlueButton.get_metadata_from_recording(doc[:recording]),
      "download" => doc.dig(:recording, :download) || {},
      "raw_size" => doc.dig(:recording, :raw_size) || {},
      "start_time" => doc.dig(:recording, :start_time) || {},
      "end_time" => doc.dig(:recording, :end_time) || {}
    }
  rescue Exception => e
    BigBlueButton.logger.warn "An exception occurred while loading the extra information for the publish event"
    BigBlueButton.logger.warn e.message
    e.backtrace.each do |traceline|
      BigBlueButton.logger.warn traceline
    end
    next
  end

  if opts[:dry_run]
    obj = {
      "publish_type" => publish_type,
      "meeting_id" => meeting_id,
      "payload" => payload
    }
    BigBlueButton.logger.info JSON.pretty_generate(obj)
  else
    BigBlueButton.redis_publisher.put_process_started(publish_type, meeting_id)
    BigBlueButton.redis_publisher.put_process_ended(publish_type, meeting_id)
    BigBlueButton.redis_publisher.put_publish_started(publish_type, meeting_id)
    BigBlueButton.redis_publisher.put_publish_ended(publish_type, meeting_id, payload)
  end

  next if visibility == "published"
  BigBlueButton.redis_publisher.put_message_workflow(visibility, publish_type, meeting_id) if ! opts[:dry_run]
end
