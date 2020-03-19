#!/usr/bin/ruby

=begin
Move this script to /usr/local/bigbluebutton/core/scripts/utils/restart-kms.rb, and add the following lines to root crontab:

* * * * * /usr/bin/ruby /usr/local/bigbluebutton/core/scripts/utils/restart-kms.rb
=end

require 'digest/sha1'
require 'nokogiri'
require 'uri'
require 'net/http'
require 'date'

kurento_launch_date = `systemctl show -p ActiveEnterTimestamp kurento-media-server.service | cut -d'=' -f2`.strip
exit 0 if ((DateTime.now - DateTime.parse(kurento_launch_date)) * 24).to_i < 6

shared_secret = `cat /usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties | grep '^securitySalt=' | cut -d'=' -f2`.strip
endpoint = `cat /usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties | grep '^bigbluebutton.web.serverURL=' | cut -d'=' -f2 | awk '{print $1"/bigbluebutton/api"}'`.strip

params = "random=#{rand(99999)}"
checksum = Digest::SHA1.hexdigest "getMeetings#{params}#{shared_secret}"
url = "#{endpoint}/getMeetings?#{params}&checksum=#{checksum}"

uri = URI.parse(url)
req = Net::HTTP::Get.new(uri.to_s)
res = Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') { |http| http.request(req) }
if res.code == "200"
    doc = Nokogiri::XML(res.body)
    if doc.xpath("/response/meetings/meeting").empty?
      puts "No meeting running, restarting Kurento and bbb-webrtc-sfu..."
      puts `systemctl stop bbb-webrtc-sfu.service kurento-media-server.service`
      pid = `pidof kurento-media-server`.strip
      if ! pid.empty?
        puts `kill -9 #{pid}`
      end
      puts `systemctl restart kurento-media-server.service bbb-webrtc-sfu.service`
    end
end
