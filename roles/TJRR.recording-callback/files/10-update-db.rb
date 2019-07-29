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
exit 0 if ! File.exists? metadata_xml

props = YAML::load(File.open(File.expand_path('../10-update-db.yml', __FILE__)))
db_username = props['db_username']
db_password = props['db_password']
db_database = props['db_database']
db_host = props['db_host']
callback_uri = props['callback_uri']

client = Mysql2::Client.new(:host => db_host,
    :username => db_username,
    :password => db_password,
    :database => db_database)

doc = Hash.from_xml(File.open(metadata_xml))
doc = JSON.parse(doc.to_json)

size = 0
uri = nil
if ! doc["recording"]["download"].nil? and ! doc["recording"]["download"]["link"].nil?
  size += doc["recording"]["download"]["size"].to_i
  uri = URI.parse(doc["recording"]["download"]["link"])
elsif ! doc["recording"]["playback"].nil? and ! doc["recording"]["playback"]["link"].nil?
  size += doc["recording"]["playback"]["size"].to_i
  uri = URI.parse(doc["recording"]["playback"]["link"])
end

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
  results = client.query("SELECT id FROM Recordings WHERE recordId = \"#{record_id}\";")
  if results.count > 0
    update_fields = data.select{ |k, v| [ "updateAt", "serverId", "serverType", "playback", "size", "metadata" ].include?(k) }.map{ |k, v| "#{k} = \"#{client.escape(v.to_s)}\""}.join(", ")
    query = "UPDATE Recordings SET #{update_fields} WHERE recordId = \"#{record_id}\";"
    BigBlueButton.logger.info "Running #{query}"
    results = client.query(query)
  else
    fields = data.map{ |k, v| k }.join(", ")
    values = data.map{ |k, v| "\"#{client.escape(v.to_s)}\"" }.join(", ")
    query = "INSERT INTO Recordings (#{fields}) VALUES (#{values});"
    BigBlueButton.logger.info "Running #{query}"
    results = client.query(query)
  end

  uri = URI("#{callback_uri}?meetingId=#{meeting_id}")
  status_response = Net::HTTP.get_response(uri)
  if status_response.kind_of? Net::HTTPSuccess
    BigBlueButton.logger.info "HTTP callback to #{uri.to_s} succeeded"
  else
    BigBlueButton.logger.info "HTTP callback to #{uri.to_s} failed with #{status_response.code} #{status_response.message}"
  end
rescue => e
  BigBlueButton.logger.info("Rescued")
  BigBlueButton.logger.info(e.to_s)
end
