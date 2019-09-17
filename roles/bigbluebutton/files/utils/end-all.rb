require 'nokogiri'
require 'cgi'
require '/usr/local/bigbluebutton/core/scripts/utils/monitoring-utils.rb'

requester = HTTPRequester.new
BBBProperties.load_properties_from_file
URIBuilder.server_url = BBBProperties.server_url
uri = URIBuilder.api_method_uri 'getMeetings'
doc = Nokogiri::XML(requester.get_response(uri).body)

exit(1) if doc.at_xpath("/response/returncode").text != "SUCCESS"

doc.xpath("//meetings/meeting").each do |meeting|
  meetingId = meeting.at_xpath("./meetingID").text
  moderatorPassword = meeting.at_xpath("./moderatorPW").text
  uri = URIBuilder.api_method_uri("end", "meetingID=#{CGI::escape(meetingId)}&password=#{moderatorPassword}")
  doc = Nokogiri::XML(requester.get_response(uri).body)
  if doc.at_xpath("/response/returncode").text == "SUCCESS"
    puts "Successfully ended #{meetingId}"
  else
    puts "Failed to end #{meetingId}"
    puts doc.to_xml(:indent => 2)
  end
end
