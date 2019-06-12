require 'nokogiri'
require 'cgi'
require '/usr/local/bigbluebutton/core/scripts/utils/monitoring-utils.rb'

requester = HTTPRequester.new
BBBProperties.load_properties_from_file
URIBuilder.server_url = BBBProperties.server_url
uri = URIBuilder.api_method_uri 'getMeetings'
doc = Nokogiri::XML(requester.get_response(uri).body)

exit(1) if doc.at_xpath("/response/returncode").text != "SUCCESS" or doc.xpath("//meetings/meeting").length > 0
