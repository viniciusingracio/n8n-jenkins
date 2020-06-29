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

opts = Trollop::options do
  opt :meeting_id, "Meeting id to archive", :type => String
  opt :dry_run, "Do not record in the database, just lookup", :type => :flag, :default => false
end

logger = if opts[:dry_run]
        Logger.new(STDOUT)
    else
        Logger.new("/var/log/bigbluebutton/post_publish.log", 'weekly' )
    end
logger.level = Logger::INFO
BigBlueButton.logger = logger

record_id = opts[:meeting_id]

metadata_xml = "/var/bigbluebutton/published/presentation/#{record_id}/metadata.xml"
if ! File.exists? metadata_xml
  BigBlueButton.logger.error "Cannot find a metadata.xml for the recording #{record_id}"
  exit 0
end

props = YAML::load(File.open(File.expand_path('../10-update-db.yml', __FILE__)))
db_username = props['db_username']
db_password = props['db_password']
db_database = props['db_database']
db_host = props['db_host']

client = Mysql2::Client.new(:host => db_host,
    :username => db_username,
    :password => db_password,
    :database => db_database)

doc = Hash.from_xml(File.open(metadata_xml))
doc = JSON.parse(doc.to_json)

doc["recording"]["playback"]["link"].strip! if ! doc.dig("recording", "playback", "link").nil?
doc["recording"]["download"]["link"].strip! if ! doc.dig("recording", "download", "link").nil?

uri = doc.dig("recording", "playback", "link") || doc.dig("recording", "download", "link")
uri = URI.parse(uri)
size = ( doc.dig("recording", "playback", "size") || doc.dig("recording", "download", "size") || 0 ).to_i

server_id = nil
server_type = nil
query = "SELECT id FROM RecordingServers WHERE address = \"#{uri.host}\";"
results = client.query(query)
if results.count > 0
  server_id = results.first["id"]
  server_type = "RecordingServer"
else
  query = "SELECT id FROM Servers WHERE address = \"#{uri.host}\";"
  results = client.query(query)
  if results.count > 0
    server_id = results.first["id"]
    server_type = "Server"
  end
end

now = DateTime.now.strftime('%Y-%m-%d %H:%M:%S')
meeting_id = doc["recording"]["meta"]["meetingId"]

data = {
  "recordId" => record_id,
  "createdAt" => now,
  "updatedAt" => now,
  "serverId" => server_id,
  "serverType" => server_type,
  "meetingId" => meeting_id,
  "name" => doc["recording"]["meta"]["meetingName"],
  "published" => doc["recording"]["published"] ? 1 : 0,
  "startTime" => doc["recording"]["start_time"],
  "endTime" => doc["recording"]["end_time"],
  "metadata" => doc["recording"]["meta"] || {},
  "playback" => doc["recording"]["playback"] || {},
  "download" => doc["recording"]["download"] || {},
  "status" => "0",
  "integrationId" => doc["recording"]["meta"]["mconflb-institution"],
  "size" => size,
  "rawSize" => doc["recording"]["raw_size"]
}

if ! data["playback"].empty?
  data["playback"]["type"] = data["playback"].delete("format")
  data["playback"]["url"] = data["playback"].delete("link")
  data["playback"]["processingTime"] = data["playback"].delete("processing_time")
  data["playback"]["length"] = (data["playback"].delete("duration").to_f / 60000).to_i

  if data["playback"].key?("extensions")
    data["playback"].delete("extensions").each do |k, v|
      data["playback"][k] = v
    end
  end

  def process_image(image)
    image["\#"] = image.delete("value").strip
    image["\@"] = image.delete("attributes")
    image
  end

  images = data.dig("playback", "preview", "images")
  if ! images.nil?
    if images.is_a?(Array)
      images.map { |k, v| [ k, process_image(image) ] }.to_h
    else
      images["image"] = process_image(images["image"])
    end
  end

  playback = data.delete("playback")
  data["playback"] = { "format" => playback }
end

if ! data["download"].empty?
  data["download"]["type"] = data["download"].delete("format")
  data["download"]["url"] = data["download"].delete("link")
  data["download"]["processingTime"] = data["download"].delete("processing_time")
  data["download"]["length"] = (data["download"].delete("duration").to_f / 60000).to_i
  download = data.delete("download")
  data["download"] = { "format" => download }
end

["playback", "metadata", "download"].each do |k|
  data[k] = data[k].to_json
end

begin
  results = client.query("SELECT * FROM Recordings WHERE recordId = \"#{record_id}\";")
  if results.count > 0
    BigBlueButton.logger.info "Results before update:\n#{JSON.pretty_generate(results.to_a)}"

    update_fields = data.select{ |k, v| [ "updateAt", "serverId", "serverType", "playback", "size", "metadata", "integrationId", "meetingId", "name" ].include?(k) }.map{ |k, v| "#{k} = \"#{client.escape(v.to_s)}\""}.join(", ")
    query = "UPDATE Recordings SET #{update_fields} WHERE recordId = \"#{record_id}\";"
    BigBlueButton.logger.info "Running #{query}"
    results = client.query(query) if ! opts[:dry_run]

    results = client.query("SELECT * FROM Recordings WHERE recordId = \"#{record_id}\";")
    BigBlueButton.logger.info "Results after update:\n#{JSON.pretty_generate(results.to_a)}"
  else
    fields = data.map{ |k, v| k }.join(", ")
    values = data.map{ |k, v| "\"#{client.escape(v.to_s)}\"" }.join(", ")
    query = "INSERT INTO Recordings (#{fields}) VALUES (#{values});"
    BigBlueButton.logger.info "Running #{query}"
    results = client.query(query) if ! opts[:dry_run]
  end
rescue => e
  BigBlueButton.logger.info("Rescued")
  BigBlueButton.logger.info(e.to_s)
end
