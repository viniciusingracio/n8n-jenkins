#!/usr/bin/ruby

require 'erb'
require 'net/http'
require 'nokogiri'
require 'trollop'
require 'digest/sha1'
require 'benchmark'

# Manage BBB properties such as server address and salt.
# These informations can be loaded from file (bigbluebutton.properties) or
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

# Build URIs to different resources available in the BBB server.
class URIBuilder
  def self.server_url=(server_url)
    @@server_url = server_url
  end

  def self.api_uri
    @@api_uri ||= build_uri "/bigbluebutton/api"
  end

  def self.create_uri
    @@create_uri ||= build_uri "/bigbluebutton/api/create"
  end

  def self.demo_uri
    @@demo_uri ||= build_uri "/demo/demo1.jsp"
  end

  def self.client_uri
    @@client_uri ||= build_uri "client/conf/config.xml"
  end

  def self.api_method_uri(method)
    get_security method do |params, checksum|
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
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = @ssl_enabled

    # It never raises an exception
    http.get(uri.request_uri)
  end

  def get_response_code(*args)
    get_response(*args).code
  end

  def process(*args)
    response = get_response(*args)

    yield(response.code, response)
  end

  def is_responding?(service)
    case service
    when 'bbb'
      service_uri = URIBuilder.api_uri
    when 'demo'
      service_uri = URIBuilder.demo_uri
    when 'client'
      service_uri = URIBuilder.client_uri
    when 'create'
      service_uri = URIBuilder.create_uri
    else
      'Invalid service'
    end

    get_response(service_uri).code == '200'
  end
end

# All monitored services need
# a HTTP requester to retrive data from BBB server, and
# a formatter to put the output in the desired format.
class MonitoredService
  def self.requester=(requester)
    @@requester = requester
  end
end

# Retrieve and process meetings information
class Meetings < MonitoredService
  def self.process_meetings
    # Meetings data can change between queries so it should be computed every time
    update_meetings

    meetings_hash = {
      :bbb_meetings_response_code => @@response_code,
      :bbb_meetings_total => 0,
      :bbb_meetings_participants_total => 0,
      :bbb_meetings_sent_videos_total => 0,
      :bbb_meetings_received_videos_total => 0,
      :bbb_meetings_sent_audio_total => 0,
      :bbb_meetings_received_audio_total => 0,
      :bbb_meetings_list => []
    }

    unless @@meetings.empty?
      meetings_hash[:bbb_meetings_total] = @@meetings.length
      @@meetings.each do |meeting|
        if meeting.at_xpath('running').text == 'true'
          participant_count = Integer(meeting.at_xpath('participantCount').text)
          listener_count = Integer(meeting.at_xpath('listenerCount').text)
          voice_participant_count = Integer(meeting.at_xpath('voiceParticipantCount').text)
          video_count = Integer(meeting.at_xpath('videoCount').text)
          meeting_name = meeting.at_xpath('meetingName').text

          meetings_hash[:bbb_meetings_list] << meeting_name
          meetings_hash[:bbb_meetings_participants_total] += participant_count
          meetings_hash[:bbb_meetings_sent_videos_total] += video_count
          meetings_hash[:bbb_meetings_received_videos_total] += video_count * (participant_count - 1)
          meetings_hash[:bbb_meetings_sent_audio_total] += voice_participant_count
          meetings_hash[:bbb_meetings_received_audio_total] += listener_count
        end
      end
    end

    meetings_hash
  end

  def self.update_meetings
    uri = URIBuilder.api_method_uri 'getMeetings'
    response = @@requester.get_response(uri)
    @@response_code = response.code
    doc = Nokogiri::XML(response.body)

    @@meetings = doc.xpath('//meeting')
  end

  private_class_method :update_meetings
end

# Retrieve and process recordings information
class Recordings < MonitoredService
  def self.process_recordings
    update_recordings

    {
      :bbb_recordings_response_code => @@response_code,
      :bbb_recordings_total => @@recordings.length,
      :bbb_recordings_response_time => @@time
    }
  end

  def self.update_recordings
    uri = URIBuilder.api_method_uri 'getRecordings'
    response = nil
    time = Benchmark.measure do
      response = @@requester.get_response(uri)
    end

    @@response_code = response.code
    @@time = time.to_s[/\(\s*([\d.]*)\)/, 1]
    doc = Nokogiri::XML(response.body)
    @@recordings = doc.xpath('//recording')
  end

  private_class_method :update_recordings
end

def parse_xml(data, xpath)
  doc = Nokogiri::XML(data.body)
  node = doc.at_xpath(xpath)

  if node.nil? then nil else node.text end
end

def fill_template(results)
  template =
  <<~HEREDOC
    # HELP bbb_recordings_response_code Response code of getRecordings call
    # TYPE bbb_recordings_response_code gauge
    bbb_recordings_response_code <%= results[:bbb_recordings_response_code] %>

    # HELP bbb_recordings_total The total number of recordings
    # TYPE bbb_recordings_total gauge
    bbb_recordings_total <%= results[:bbb_recordings_total] %>

    # HELP bbb_recordings_response_time The response time for recordings
    # TYPE bbb_recordings_response_time gauge
    bbb_recordings_response_time <%= results[:bbb_recordings_response_time] %>
  HEREDOC

  ERB.new(template).result
end


opts = Trollop::options do
  opt :server, "Server address in format '<scheme://<addr>:<port>/bigbluebutton'", :type => :string # --host, default nil
  opt :salt, "Salt of BBB server", :type => :string # --salt, default nil
  opt :ssl, "Enable secure HTTP with SSL" # --ssl, default false
end


# If server or salt are not passed as arguments,
# load properties from bigbluebutton.properties.
unless opts[:server] and opts[:salt]
  BBBProperties.load_properties_from_file
else
  BBBProperties.load_properties_from_cli(opts[:server], opts[:salt])
end

if BBBProperties.server_url =~ /^http[s]?:\/\//
  URIBuilder.server_url = BBBProperties.server_url
else
  URIBuilder.server_url = (opts[:ssl] ? "https://" : "http://") + BBBProperties.server_url
end

requester = HTTPRequester.new(opts[:ssl])

Meetings.requester = requester
Recordings.requester = requester

results = Hash.new(0)

results.merge!(Recordings.process_recordings)

filled_template = fill_template(results)

puts filled_template
