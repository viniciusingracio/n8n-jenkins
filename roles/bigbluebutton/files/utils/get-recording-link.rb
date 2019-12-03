#!/usr/bin/ruby

require 'digest/sha1'
require 'cgi'
require 'optimist'
require 'yaml'
require 'nokogiri'
require 'uri'
require 'net/http'

opts = Optimist::options do
  opt :server, "", :type => String, :required => true
  opt :salt, "", :type => String, :required => true
  opt :record_id, "", :type => String, :required => true
  opt :full_name, "", :type => String, :default => "Felipe Cecagno"
  opt :ip, "", :type => String
end

ip = opts[:ip]
if ip.nil?
    uri = URI.parse("https://ipinfo.io/ip")
    req = Net::HTTP::Get.new(uri.to_s)
    res = Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') { |http| http.request(req) }
    if res.code != "200"
        exit 1
    end

    ip = res.body.strip
end
server = opts[:server]
record_id = opts[:record_id]
full_name = opts[:full_name]

params = "meetingID=#{record_id}&authUser=#{CGI::escape(full_name)}&authAddr=#{ip}&action=edit"
checksum = Digest::SHA1.hexdigest "getRecordingToken#{params}#{opts[:salt]}"
url = "https://#{server}/bigbluebutton/api/getRecordingToken?#{params}&checksum=#{checksum}"

uri = URI.parse(url)
req = Net::HTTP::Get.new(uri.to_s)
res = Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') { |http| http.request(req) }
token = nil
if res.code == "200"
    doc = Nokogiri::XML(res.body)
    token = doc.at_xpath("//token").text
end

params = "recordID=#{record_id}"
checksum = Digest::SHA1.hexdigest "getRecordings#{params}#{opts[:salt]}"
url = "https://#{server}/bigbluebutton/api/getRecordings?#{params}&checksum=#{checksum}"

uri = URI.parse(url)
req = Net::HTTP::Get.new(uri.to_s)
res = Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') { |http| http.request(req) }
if res.code == "200"
    doc = Nokogiri::XML(res.body)
    doc.xpath("//playback/format/url").each do |node|
        playback_url = node.text
        if ! token.nil?
            if playback_url.split("?").length == 1
                puts "#{playback_url}?token=#{token}"
            else
                puts "#{playback_url}&token=#{token}"
            end
        else
            puts playback_url
        end
        puts
    end
end
puts "https://#{server}/editor/captions/#{record_id}/edit?token=#{token}"
