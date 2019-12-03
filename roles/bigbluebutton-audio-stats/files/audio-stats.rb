require 'open4'
require 'pp'
require 'json'
require 'nokogiri'
require 'redis'
require 'yaml'
require 'net/http'
require 'digest/sha1'
require 'benchmark'
require 'logger'
require 'histogram/array'
require 'erb'

=begin
add the following lines to root crontab:

* * * * * sleep 30; /usr/bin/ruby /usr/local/bigbluebutton/core/scripts/utils/audio-stats.rb
* * * * * sleep 60; /usr/bin/ruby /usr/local/bigbluebutton/core/scripts/utils/audio-stats.rb
=end

# manage BBB properties such as server address and salt.
# these informations can be loaded from file (bigbluebutton.properties) or
# externally set (for instance, from command line).
class BBBProperties
  def self.load_properties_from_file()
    servlet_dir = File.exists?("/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties") ? "/usr/share/bbb-web" : "/var/lib/tomcat7/webapps/bigbluebutton"
    @@properties = Hash[File.read("#{servlet_dir}/WEB-INF/classes/bigbluebutton.properties", :encoding => "ISO-8859-1:UTF-8").scan(/(.+?)=(.+)/)]
  end

  def self.load_properties_from_cli(server_url, salt)
    @@properties = Hash.new(0)
    @@properties['bigbluebutton.web.serverURL'] = server_url
    @@properties['securitySalt'] = salt
  end

  def self.server_url
    @@server_url ||= get_properties 'bigbluebutton.web.serverURL'
  end

  def self.security_salt
    @@security_salt ||= get_properties 'securitySalt'
  end

  def self.get_properties(property)
    begin
      @@properties[property]
    rescue Errno::ENOENT => errno
      puts "error: #{errno}"
      exit
    end
  end

  private_class_method :get_properties
end

# build URIs to different resources available in the BBB server.
class URIBuilder
  def self.server_url=(server_url)
    @@server_url = server_url
  end

  def self.api_uri
    @@api_uri ||= build_uri "/bigbluebutton/api"
  end

  def self.demo_uri
    @@demo_uri ||= build_uri "/demo/demo1.jsp"
  end

  def self.client_uri
    @@client_uri ||= build_uri "client/conf/config.xml"
  end

  def self.api_method_uri(method)
    @@method_uri ||= get_security method do |params, checksum|
      "bigbluebutton/api/#{method}?#{params}&checksum=#{checksum}"
    end
  end

  def self.build_uri(path)
    begin
      URI::join(@@server_url, path)
    rescue ArgumentError => errno
      puts "error: #{errno}"
      exit
    end
  end

  def self.get_security(method)
    params = "random=#{rand(99999)}"
    checksum = Digest::SHA1.hexdigest "#{method}#{params}#{BBBProperties.security_salt}"
    build_uri yield(params, checksum)
  end

  private_class_method :build_uri, :get_security
end

# HTTP connection manager to retrieve informations from the BBB server.
class HTTPRequester
  attr_accessor :ssl_enabled

  def initialize(ssl_enabled = false)
    @ssl_enabled = ssl_enabled
  end

  def get_response(uri)
    uri.scheme, uri.port = @ssl_enabled ? ['https',443] : ['http',80]
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = @ssl_enabled

    # It never raises an exception
    http.get(uri.request_uri)
  end

  def get_response_code(*args)
    get_response(*args).code
  end

  def is_responding?(service)
    case service
    when 'bbb'
      service_uri = URIBuilder.api_uri
    when 'demo'
      service_uri = URIBuilder.demo_uri
    when 'client'
      service_uri = URIBuilder.client_uri
    else
      'Invalid service'
    end

    get_response(service_uri).code == '200'
  end
end

class Hash
  class << self
    def from_xml(xml_io)
      begin
        result = Nokogiri::XML(xml_io)
        return { result.root.name.to_sym => xml_node_to_hash(result.root)}
      rescue Exception => e
        # raise your custom exception here
      end
    end

    def xml_node_to_hash(node)
      # If we are at the root of the document, start the hash
      if node.element?
        result_hash = {}
        if node.attributes != {}
          result_hash[:attributes] = {}
          node.attributes.keys.each do |key|
            result_hash[:attributes][node.attributes[key].name.to_sym] = prepare(node.attributes[key].value)
          end
        end
        if node.children.size > 0
          node.children.each do |child|
            result = xml_node_to_hash(child)

            if child.name == "text"
              unless child.next_sibling || child.previous_sibling
                if result_hash[:attributes]
                  result_hash['value'] = prepare(result)
                  return result_hash
                else
                  return prepare(result)
                end
              end
            elsif result_hash[child.name.to_sym]
              if result_hash[child.name.to_sym].is_a?(Object::Array)
                result_hash[child.name.to_sym] << prepare(result)
              else
                result_hash[child.name.to_sym] = [result_hash[child.name.to_sym]] << prepare(result)
              end
            else
              result_hash[child.name.to_sym] = prepare(result)
            end
          end

          return result_hash
        else
          return result_hash
        end
      else
        return prepare(node.content.to_s)
      end
    end

    def prepare(data)
      (data.class == String && data.to_i.to_s == data) ? data.to_i : data
    end
  end

  def to_struct(struct_name)
      Struct.new(struct_name,*keys).new(*values)
  end
end

output = ""
command = "/opt/freeswitch/bin/fs_cli -x 'show channels as json'"
Open4::popen4(command) do |pid, stdin, stdout, stderr|
  output = stdout.readlines
end

voice_data = JSON.parse(output.join(), symbolize_names: true)[:rows] || []

voice_data.each do |row|
  row[:listen_only] = ! /^GLOBAL_AUDIO.*/.match(row[:cid_name]).nil?
  m = /(?<user_id>.*)-bbbID-(?<user_name>.*)/.match(row[:cid_name])
  if ! m.nil?
    row[:user_id] = m["user_id"]
    row[:user_name] = m["user_name"]
  end
  row[:voice_bridge] = row[:dest].gsub(/^9196/, "")
  row[:is_echo] = row[:application] == "echo"
  row[:is_conference] = row[:application] == "conference"

  stats_query = {
    'command' => 'mediaStats',
    'data' => {
      'uuid' => row[:uuid]
    }
  }
  command = "/opt/freeswitch/bin/fs_cli -x 'json #{JSON.dump(stats_query)}'"
  Open4::popen4(command) do |pid, stdin, stdout, stderr|
    output = stdout.readlines
  end
  response = JSON.parse(output.join(), symbolize_names: true)
  next if response[:status] != "success"

  row[:stats] = response[:response]
  row[:timestamp] = DateTime.now
end

data = voice_data.select{ |item| item[:is_conference] }.map{ |item| item[:stats][:audio][:in_quality_percentage] }
data_sum = 0
data.each { |x| data_sum += x }
(bins, freqs) = data.histogram([ 0, 25, 50, 60, 70, 80, 85, 90, 95, 100 ], :bin_boundary => :min)
sum = 0
freqs.map! { |x| sum += x }

# https://prometheus.io/docs/instrumenting/exposition_formats/#text-format-example
template =
<<~HEREDOC
  # HELP bbb_audio_quality A histogram of audio quality
  # TYPE bbb_audio_quality histogram
  <% bins.each_with_index do |bin, index| -%>
  bbb_audio_quality_bucket{le="<%= bin.to_i %>"} <%= freqs[index].to_i %>
  <% end -%>
  bbb_audio_quality_bucket{le="+Inf"} <%= freqs.last.to_i %>
  bbb_audio_quality_sum <%= data_sum %>
  bbb_audio_quality_count <%= freqs.last.to_i %>
HEREDOC

puts ERB.new(template, nil, '-').result

requester = HTTPRequester.new
BBBProperties.load_properties_from_file
URIBuilder.server_url = BBBProperties.server_url
uri = URIBuilder.api_method_uri 'getMeetings'
doc = Nokogiri::XML(requester.get_response(uri).body)

output = Hash.from_xml(doc.to_s)
participants = []
if output[:response][:returncode] == "SUCCESS" and ! output[:response][:meetings].nil?
  output[:response][:meetings][:meeting] = [ output[:response][:meetings][:meeting] ] if output[:response][:meetings][:meeting].is_a?(Hash)
  output[:response][:meetings][:meeting].each do |meeting|
    next if meeting[:attendees].is_a?(String)
    meeting[:attendees] = meeting[:attendees][:attendee]
    meeting[:attendees] = [ meeting[:attendees] ] if meeting[:attendees].is_a?(Hash)
    meeting[:attendees].each do |attendee|
      attendee[:meeting] = Marshal.load(Marshal.dump(meeting))
      attendee[:audio] = voice_data.select do |row|
        if attendee[:clientType] == "DIAL-IN"
          attendee[:fullName] == row[:cid_name]
        else
          attendee[:userID] == row[:user_id]
        end
      end.first || {}
      attendee[:meeting].delete(:attendees)
      participants << attendee
    end
  end
end

logger = Logger.new("/var/log/bigbluebutton/audio-stats.log")
formatter = Logger::Formatter.new
logger.formatter = proc { |severity, datetime, progname, msg|
  formatter.call(severity, datetime.utc, progname, msg)
}

participants.each do | participant|
  logger.info participant.to_json
end
