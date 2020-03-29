#!/usr/bin/ruby

require 'uri'
require 'net/http'

url = "https://live-do02-test16.elos.vc/status"

uri = URI.parse(url)
req = Net::HTTP::Get.new(uri.to_s)

begin
  puts "Testing now"
  res = Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') { |http| http.request(req) } rescue nil
end until ( ! res.nil? and res.code == "200" ) or not sleep 10
