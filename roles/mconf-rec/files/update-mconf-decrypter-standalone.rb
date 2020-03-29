#!/usr/bin/ruby

require 'digest/sha1'
require 'cgi'
require 'trollop'
require 'yaml'
require 'csv'

opts = Trollop::options do
  opt :api_server, "API server, example: lb.mconf.rnp.br", :type => :string, :required => true
  opt :csv_file, "CSV file with the shared secrets", :type => :string, :required => true
  opt :stdout, "Print to stdout instead of file", :type => :flag
end

api_entry_point = "https://#{opts[:api_server]}/bigbluebutton/api"

get_recordings = []
table = CSV.parse(File.read(opts[:csv_file]), headers: true)
table.each do |line|
    integration_name = CGI::escape(line["Name"].strip)
    integration_salt = line["Secret"].strip
    params = "integrationName=#{integration_name}&meta_mconf-decrypter-pending=true"
    checksum = Digest::SHA1.hexdigest "getRecordings#{params}#{integration_salt}"
    get_recordings << "#{api_entry_point}/getRecordings?#{params}&checksum=#{checksum}"
end

if opts[:stdout]
    get_recordings.each do |api_call|
        puts "- #{api_call}"
    end
    exit 0
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
