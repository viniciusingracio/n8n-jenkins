#!/usr/bin/ruby

require 'digest/sha1'
require 'cgi'
require 'trollop'
require 'yaml'

opts = Trollop::options do
  opt :api_server, "", :type => String, :required => true
  opt :rec_server, "", :type => String, :required => true
end

api_entry_point = "https://#{opts[:api_server]}/bigbluebutton/api"
recording_server = CGI::escape("https://#{opts[:rec_server]}")

get_recordings = []
while gets()
    line = $_.split("\t")
    integration_name = CGI::escape(line[0].strip)
    integration_salt = line[1].strip

    params = "integrationName=#{integration_name}&meta_mconflb-rec-server-url=#{recording_server}&meta_mconf-decrypter-pending=true"
    checksum = Digest::SHA1.hexdigest "getRecordings#{params}#{integration_salt}"
    get_recordings << "#{api_entry_point}/getRecordings?#{params}&checksum=#{checksum}"
end

if ! get_recordings.empty?
    db_file = '/usr/local/bigbluebutton/core/scripts/mconf-decrypter.yml'
    text = File.read db_file
    properties = YAML.load text
    properties['get_recordings_url'] = get_recordings
    file = File.open(db_file, 'w')
    file.write properties.to_yaml
    file.close
    
    puts "get_recordings_url updated"
else
    puts "get_recordings empty"
end
