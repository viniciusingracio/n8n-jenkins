require '/usr/local/bigbluebutton/core/lib/recordandplayback.rb'
require 'trollop'

opts = Trollop::options do
  opt :metadata_xml_path, "Metadata file to repost event", :type => String
  opt :dry_run, "Do not execute anything", :type => :flag, :default => false
end

if ! opts[:dry_run]
  props = YAML::load(File.open('/usr/local/bigbluebutton/core/scripts/bigbluebutton.yml'))
  redis_host = props['redis_host']
  redis_port = props['redis_port']
  redis_password = props['redis_password']
  BigBlueButton.redis_publisher = BigBlueButton::RedisWrapper.new(redis_host, redis_port, redis_password)
end

list = opts[:metadata_xml_path].nil? ? Dir.glob( "/var/bigbluebutton/published/**/metadata.xml" ) : [ opts[:metadata_xml_path] ]
list.each do |metadata_xml_path|
  next if ! File.exists? metadata_xml_path
  match = /\/var\/bigbluebutton\/(?<visibility>\w+)\/(?<format>\w+)\/(?<record_id>\w+-\d+)\/metadata.xml/.match metadata_xml_path
  next if match.nil?
  meeting_id = match[:record_id]
  publish_type = match[:format]
  playback = {}
  metadata = {}
  download = {}
  raw_size = {}
  start_time = {}
  end_time = {}
  step_succeeded = true
  step_time = 0
  begin
    doc = Hash.from_xml(File.open(metadata_xml_path))
    playback = doc[:recording][:playback] if ! doc[:recording][:playback].nil?

    xml_doc = Nokogiri::XML(File.open(metadata_xml_path)) { |x| x.noblanks }
    playback[:extensions][:preview][:images][:image] = [ playback[:extensions][:preview][:images][:image] ] if xml_doc.xpath("/recording/playback/extensions/preview/images/image").size == 1

    metadata = doc[:recording][:meta] if ! doc[:recording][:meta].nil?
    download = doc[:recording][:download] if ! doc[:recording][:download].nil?
    raw_size = doc[:recording][:raw_size] if ! doc[:recording][:raw_size].nil?
    start_time = doc[:recording][:start_time] if ! doc[:recording][:start_time].nil?
    end_time = doc[:recording][:end_time] if ! doc[:recording][:end_time].nil?
  rescue Exception => e
    BigBlueButton.logger.warn "An exception occurred while loading the extra information for the publish event"
    BigBlueButton.logger.warn e.message
    e.backtrace.each do |traceline|
      BigBlueButton.logger.warn traceline
    end
    next
  end

  payload = {
    "success" => step_succeeded,
    "step_time" => step_time,
    "playback" => playback,
    "metadata" => metadata,
    "download" => download,
    "raw_size" => raw_size,
    "start_time" => start_time,
    "end_time" => end_time
  }
  if opts[:dry_run]
    obj = {
      "publish_type" => publish_type,
      "meeting_id" => meeting_id,
      "payload" => payload
    }
    BigBlueButton.logger.info JSON.pretty_generate(obj)
  else
    BigBlueButton.redis_publisher.put_publish_ended(publish_type, meeting_id, payload)
  end
end
