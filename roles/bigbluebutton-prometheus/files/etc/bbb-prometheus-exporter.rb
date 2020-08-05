#!/usr/bin/ruby

require 'erb'
require 'net/http'
require 'nokogiri'
require 'trollop'
require 'digest/sha1'
require 'benchmark'
require 'uri'
require 'docker'
require 'date'
require 'open4'
require 'json'

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
    @@client_uri ||= build_uri "/html5client"
  end

  def self.api_method_uri(method, params = nil)
    get_security(method, params) do |params, checksum|
      params += "&" if ! params.empty?
      params += "checksum=#{checksum}"
      "bigbluebutton/api/#{method}?#{params}"
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

  def self.get_security(method, params = nil)
    params ||= "random=#{rand(99999)}"
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

  def get_response(uri, **params)
    use_ssl = params.has_key?(:use_ssl) ? params[:use_ssl] : @ssl_enabled
    response = nil
    Net::HTTP.start(uri.host, uri.port, :use_ssl => use_ssl, :read_timeout => 10) do |http|
      request = Net::HTTP::Get.new uri
      response = http.request request
    end
    response
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
      :bbb_meetings_success => @@success,
      :bbb_meetings_response_code => @@response_code,
      :bbb_meetings_total => 0,
      :bbb_meetings_response_time => @@time,
      :bbb_meetings_participants_total => 0,
      :bbb_meetings_sent_videos_total => 0,
      :bbb_meetings_max_sent_videos => 0,
      :bbb_meetings_received_videos_total => 0,
      :bbb_meetings_sent_audio_total => 0,
      :bbb_meetings_received_audio_total => 0,
      :bbb_meetings_list => []
    }

    unless @@meetings.empty?
      meetings_hash[:bbb_meetings_total] = @@meetings.length
      @@meetings.each do |meeting|
        if meeting.at_xpath('running').text == 'true'
          participant_count = meeting.at_xpath('participantCount').text.to_i
          listener_count = meeting.at_xpath('listenerCount').text.to_i
          voice_participant_count = meeting.at_xpath('voiceParticipantCount').text.to_i
          video_count = meeting.at_xpath('videoCount').text.to_i
          meeting_name = meeting.at_xpath('meetingName').text

          meetings_hash[:bbb_meetings_list] << meeting_name
          meetings_hash[:bbb_meetings_participants_total] += participant_count
          meetings_hash[:bbb_meetings_sent_videos_total] += video_count
          meetings_hash[:bbb_meetings_max_sent_videos] = [ meetings_hash[:bbb_meetings_max_sent_videos], video_count ].max
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
    response = nil
    time = Benchmark.measure do
      response = @@requester.get_response(uri) rescue nil
    end

    @@time = time.to_s[/\(\s*([\d.]*)\)/, 1]
    if response
      @@response_code = response.code
      doc = Nokogiri::XML(response.body)
      @@meetings = doc.xpath('/response/meetings/meeting')
      node = doc.at_xpath('/response/returncode')
      @@success = ( ! node.nil? and node.text == "SUCCESS" ) ? 1 : 0
    else
      @@success = 0
      @@response_code = "NaN"
      @@meetings = []
    end
  end

  private_class_method :update_meetings
end

# Retrieve and process recordings information
class Recordings < MonitoredService
  def self.process_recordings
    update_recordings

    {
      :bbb_recordings_success => @@success,
      :bbb_recordings_response_code => @@response_code,
      :bbb_recordings_total => @@recordings.length,
      :bbb_recordings_response_time => @@time,
      :bbb_recordings_published_presentation_count => Dir.glob("/var/bigbluebutton/published/presentation/*").count,
      :bbb_recordings_published_presentation_video_count => Dir.glob("/var/bigbluebutton/published/presentation_video/*").count,
      :bbb_recordings_published_mconf_encrypted_count => Dir.glob("/var/bigbluebutton/published/mconf_encrypted/*").count,
      :bbb_recordings_unpublished_presentation_count => Dir.glob("/var/bigbluebutton/unpublished/presentation/*").count,
      :bbb_recordings_unpublished_presentation_video_count => Dir.glob("/var/bigbluebutton/unpublished/presentation_video/*").count,
      :bbb_recordings_unpublished_mconf_encrypted_count => Dir.glob("/var/bigbluebutton/unpublished/mconf_encrypted/*").count,
      :bbb_recordings_deleted_presentation_count => Dir.glob("/var/bigbluebutton/deleted/presentation/*").count,
      :bbb_recordings_deleted_presentation_video_count => Dir.glob("/var/bigbluebutton/deleted/presentation_video/*").count,
      :bbb_recordings_deleted_mconf_encrypted_count => Dir.glob("/var/bigbluebutton/deleted/mconf_encrypted/*").count,
      :bbb_recordings_sanity_count => Dir.glob("/var/bigbluebutton/recording/status/sanity/*").count,
      :bbb_recordings_fail_count => Dir.glob("/var/bigbluebutton/recording/status/**/*.fail").count,
    }
  end

  def self.update_recordings
    uri = URIBuilder.api_method_uri('getRecordings', '')
    response = nil
    time = Benchmark.measure do
      response = @@requester.get_response(uri) rescue nil
    end

    @@time = time.to_s[/\(\s*([\d.]*)\)/, 1]
    if response
      @@response_code = response.code
      doc = Nokogiri::XML(response.body)
      @@recordings = doc.xpath('/response/recordings/recording')
      node = doc.at_xpath('/response/returncode')
      @@success = ( ! node.nil? and node.text == "SUCCESS" ) ? 1 : 0
    else
      @@success = 0
      @@response_code = "NaN"
      @@recordings = []
    end
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
    # HELP bbb_api_success Success on /bigbluebutton/api call
    # TYPE bbb_api_success gauge
    bbb_api_success <%= results[:bbb_api_success] %>

    # HELP bbb_api_response_code Response code of the BBB API
    # TYPE bbb_api_response_code gauge
    bbb_api_response_code <%= results[:bbb_api_response_code] %>

    # HELP bbb_demo_response_code Response code of the demo API
    # TYPE bbb_demo_response_code gauge
    bbb_demo_response_code <%= results[:bbb_demo_response_code] %>

    # HELP bbb_meetings_success Success on /bigbluebutton/api/getMeetings call
    # TYPE bbb_meetings_success gauge
    bbb_meetings_success <%= results[:bbb_meetings_success] %>

    # HELP bbb_meetings_response_code Response code of getMeetings call
    # TYPE bbb_meetings_response_code gauge
    bbb_meetings_response_code <%= results[:bbb_meetings_response_code] %>

    # HELP bbb_meetings_response_time The response time for getMeetings
    # TYPE bbb_meetings_response_time gauge
    bbb_meetings_response_time <%= results[:bbb_meetings_response_time] %>

    # HELP bbb_meetings_total The total number of meetings running
    # TYPE bbb_meetings_total gauge
    bbb_meetings_total <%= results[:bbb_meetings_total] %>

    # HELP bbb_meetings_participants_total The total number of participants
    # TYPE bbb_meetings_participants_total gauge
    bbb_meetings_participants_total <%= results[:bbb_meetings_participants_total] %>

    # HELP bbb_meetings_sent_videos The total number of videos
    # TYPE bbb_meetings_sent_videos gauge
    bbb_meetings_sent_videos <%= results[:bbb_meetings_sent_videos_total] %>

    # HELP bbb_meetings_received_videos The total number of videos received
    # TYPE bbb_meetings_received_videos gauge
    bbb_meetings_received_videos <%= results[:bbb_meetings_received_videos_total] %>

    # HELP bbb_meetings_max_sent_videos The max number of cameras in a session
    # TYPE bbb_meetings_max_sent_videos gauge
    bbb_meetings_max_sent_videos <%= results[:bbb_meetings_max_sent_videos] %>

    # HELP bbb_meetings_sent_audio The total number of audio sent
    # TYPE bbb_meetings_sent_audio gauge
    bbb_meetings_sent_audio <%= results[:bbb_meetings_sent_audio_total] %>

    # HELP bbb_meetings_received_audio The total number of audio received
    # TYPE bbb_meetings_received_audio gauge
    bbb_meetings_received_audio <%= results[:bbb_meetings_received_audio_total] %>

    # HELP bbb_recordings_success Success on /bigbluebutton/api/getRecordings call
    # TYPE bbb_recordings_success gauge
    bbb_recordings_success <%= results[:bbb_recordings_success] %>

    # HELP bbb_recordings_total The total number of recordings
    # TYPE bbb_recordings_total gauge
    bbb_recordings_total <%= results[:bbb_recordings_total] %>

    # HELP bbb_recordings_response_time The response time for recordings
    # TYPE bbb_recordings_response_time gauge
    bbb_recordings_response_time <%= results[:bbb_recordings_response_time] %>

    # HELP bbb_recordings_response_code Responde code of getRecordings call
    # TYPE bbb_recordings_response_code gauge
    bbb_recordings_response_code <%= results[:bbb_recordings_response_code] %>

    # HELP bbb_recordings_count The number of recordings for each visibility and format
    # TYPE bbb_recordings_count gauge
    bbb_recordings_count{visibility="published",format="presentation"} <%= results[:bbb_recordings_published_presentation_count] %>
    bbb_recordings_count{visibility="published",format="presentation_video"} <%= results[:bbb_recordings_published_presentation_video_count] %>
    bbb_recordings_count{visibility="published",format="mconf_encrypted"} <%= results[:bbb_recordings_published_mconf_encrypted_count] %>
    bbb_recordings_count{visibility="unpublished",format="presentation"} <%= results[:bbb_recordings_unpublished_presentation_count] %>
    bbb_recordings_count{visibility="unpublished",format="presentation_video"} <%= results[:bbb_recordings_unpublished_presentation_video_count] %>
    bbb_recordings_count{visibility="unpublished",format="mconf_encrypted"} <%= results[:bbb_recordings_unpublished_mconf_encrypted_count] %>
    bbb_recordings_count{visibility="deleted",format="presentation"} <%= results[:bbb_recordings_deleted_presentation_count] %>
    bbb_recordings_count{visibility="deleted",format="presentation_video"} <%= results[:bbb_recordings_deleted_presentation_video_count] %>
    bbb_recordings_count{visibility="deleted",format="mconf_encrypted"} <%= results[:bbb_recordings_deleted_mconf_encrypted_count] %>

    # HELP bbb_recordings_sanity_count The number of pending recordings
    # TYPE bbb_recordings_sanity_count gauge
    bbb_recordings_sanity_count <%= results[:bbb_recordings_sanity_count] %>

    # HELP bbb_recordings_fail_count The number of failed recordings
    # TYPE bbb_recordings_fail_count gauge
    bbb_recordings_fail_count <%= results[:bbb_recordings_fail_count] %>

    # HELP bbb_api_create_response_code Response code of the create endpoint of the API
    # TYPE bbb_api_create_response_code gauge
    bbb_api_create_response_code{method="get",messageKey="<%= results[:bbb_api_create_message_key] %>"} <%= results[:bbb_api_create_response_code] %>

    # HELP bbb_webhook_success Success calling the webhook endpoint
    # TYPE bbb_webhook_success gauge
    bbb_webhook_success <%= results[:bbb_webhook_success] %>

    # HELP bbb_webhook_queue_length Webhooks queue length
    # TYPE bbb_webhook_queue_length gauge
    bbb_webhook_queue_length <%= results[:bbb_webhook_queue_length] %>
<% if results.has_key? :bbb_webhook_response_code %>
    # HELP bbb_webhook_code Response code of the create endpoint of the API
    # TYPE bbb_webhook_code gauge
    bbb_webhook_response_code{method="get",host="<%= results.has_key?(:bbb_webhook_host) ? results[:bbb_webhook_host] : nil %>"} <%= results[:bbb_webhook_response_code] %>
<% end %>
    # HELP bbb_webhook_response_time The response time for webhooks GET
    # TYPE bbb_webhook_response_time gauge
    bbb_webhook_response_time <%= results[:bbb_webhook_response_time] %>

    # HELP bbb_client_success Success calling the html5 client endpoint
    # TYPE bbb_client_success gauge
    bbb_client_success <%= results[:bbb_client_success] %>

    # HELP bbb_total_time Generation time for all the data
    # TYPE bbb_total_time gauge
    bbb_total_time <%= results[:bbb_total_time] %>

    # HELP bbb_freeswitch_cli_success fs_cli connected successfully
    # TYPE bbb_freeswitch_cli_success gauge
    bbb_freeswitch_cli_success <%= results[:bbb_freeswitch_cli_success] %>
<% if results[:bbb_freeswitch_cli_success] %>
    # HELP bbb_freeswitch_clock_drift Clock drift of FreeSWITCH compared to the system
    # TYPE bbb_freeswitch_clock_drift gauge
    bbb_freeswitch_clock_drift <%= results[:bbb_freeswitch_clock_drift] %>

    # HELP bbb_freeswitch_channels_full_audio Full audio channels on FreeSWITCH
    # TYPE bbb_freeswitch_channels_full_audio gauge
    bbb_freeswitch_channels_full_audio <%= results[:bbb_freeswitch_channels_full_audio] %>

    # HELP bbb_freeswitch_channels_listen_only_freeswitch Listen only channels for individuals on FreeSWITCH
    # TYPE bbb_freeswitch_channels_listen_only_freeswitch gauge
    bbb_freeswitch_channels_listen_only_freeswitch <%= results[:bbb_freeswitch_channels_listen_only_freeswitch] %>

    # HELP bbb_freeswitch_channels_listen_only_kurento Listen only channels for rooms on FreeSWITCH
    # TYPE bbb_freeswitch_channels_listen_only_kurento gauge
    bbb_freeswitch_channels_listen_only_kurento <%= results[:bbb_freeswitch_channels_listen_only_kurento] %>
<% end %>
<% if results.has_key? :bbb_freeswitch_audio_score %>
    # HELP bbb_freeswitch_audio_score Audio score for full audio channels on FreeSWITCH
    # TYPE bbb_freeswitch_audio_score gauge
    bbb_freeswitch_audio_score <%= results[:bbb_freeswitch_audio_score] %>
<% end %>
    # HELP bbb_streaming_count Number of containers running for streaming
    # TYPE bbb_streaming_count gauge
    bbb_streaming_count <%= results[:bbb_streaming_count] %>

    # HELP bbb_recorder_count Number of containers running for presentation_video recording
    # TYPE bbb_recorder_count gauge
    bbb_recorder_count <%= results[:bbb_recorder_count] %>
  HEREDOC

  ERB.new(template).result
end

results = Hash.new(0)

results[:bbb_total_time] = Benchmark.measure do
  opts = Trollop::options do
    opt :server, "Server address in format '<scheme://<addr>:<port>/bigbluebutton'", :type => :string # --host, default nil
    opt :salt, "Salt of BBB server", :type => :string # --salt, default nil
    opt :ssl, "Enable secure HTTP with SSL" # --ssl, default false
    opt :webhook, "Webhook URL to check", :type => :string
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

  response = requester.get_response(URIBuilder.api_uri) rescue nil
  if response
    results[:bbb_api_response_code] = response.code
    doc = Nokogiri::XML(response.body)
    node = doc.at_xpath('/response/returncode')
    results[:bbb_api_success] = ( ! node.nil? and node.text == "SUCCESS" ) ? 1 : 0
  else
    results[:bbb_api_response_code] = "NaN"
    results[:bbb_api_success] = 0
  end

  results[:bbb_api_create_response_code], results[:bbb_api_create_message_key] = requester.process(URIBuilder.create_uri) do |code, data|
    message_key = parse_xml(data, "/response/messageKey")

    [code, message_key]
  end rescue [ "NaN", "" ]

  results[:bbb_client_success] = requester.is_responding?('client') ? 1 : 0

  all_containers = Docker::Container.all(:all => true)
  # make sure we the docker container is running if we're running the webooks on docker
  container = all_containers.select{ |container| container.info["Names"].first == "/webhooks" }
  if container.empty? || container.first.info["State"] == "running"
    results[:bbb_webhook_success] = 1
  else
    results[:bbb_webhook_success] = 0
  end

  results[:bbb_streaming_count] = all_containers.select{ |container| container.info["Names"].first.start_with?("/streaming_") and container.info["State"] == "running" }.length
  results[:bbb_recorder_count] = all_containers.select{ |container| container.info["Names"].first.start_with?("/record_") and container.info["State"] == "running" }.length

  if opts[:webhook]
    uri = URI.parse(opts[:webhook])
    results[:bbb_webhook_host] = uri.host
    response = nil
    time = Benchmark.measure do
      response = requester.get_response(uri, use_ssl: uri.scheme == "https" ) rescue nil
    end

    results[:bbb_webhook_queue_length] = `redis-cli llen bigbluebutton:webhooks:events:1 | sed 's/(integer)//g'`.strip.to_i
    results[:bbb_webhook_response_time] = time.to_s[/\(\s*([\d.]*)\)/, 1]
    if response
      results[:bbb_webhook_success] = ( response.code == "200" ) ? 1 : 0
      results[:bbb_webhook_response_code] = response.code
    else
      results[:bbb_webhook_success] = 0
    end
  end

  begin
    results[:bbb_freeswitch_clock_drift] = (DateTime.parse(`/opt/freeswitch/bin/fs_cli -x "strftime"`) - DateTime.now).to_i
    results[:bbb_freeswitch_cli_success] = 1

    output = ""
    command = "/opt/freeswitch/bin/fs_cli -x 'show channels as json'"
    Open4::popen4(command) do |pid, stdin, stdout, stderr|
      output = stdout.readlines
    end

    voice_data = JSON.parse(output.join(), symbolize_names: true)[:rows] || []
    full_audio_regex = /.*-bbbID-.*/
    listen_only_freeswitch_regex = /.*-bbbID-LISTENONLY-.*/
    listen_only_kurento_regex = /^GLOBAL_AUDIO_\d+$/

    audio_score_list = []
    full_audio_data = voice_data.select{ |row| ! full_audio_regex.match(row[:cid_name]).nil? and listen_only_freeswitch_regex.match(row[:cid_name]).nil? }
    full_audio_data.each do |row|
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
      audio_score = response.dig(:response, :audio, :in_quality_percentage)
      next if audio_score.nil?
      audio_score_list << audio_score.to_i
    end

    results[:bbb_freeswitch_audio_score] = ( audio_score_list.inject{ |sum, el| sum + el }.to_f / audio_score_list.size ) if ! audio_score_list.empty?
    results[:bbb_freeswitch_channels_full_audio] = full_audio_data.length
    results[:bbb_freeswitch_channels_listen_only_freeswitch] = voice_data.select{ |row| ! listen_only_freeswitch_regex.match(row[:cid_name]).nil? }.length
    results[:bbb_freeswitch_channels_listen_only_kurento] = voice_data.select{ |row| ! listen_only_kurento_regex.match(row[:cid_name]).nil? }.length
  rescue Exception => e
    results[:bbb_freeswitch_cli_success] = 0
  end

  results.merge!(Meetings.process_meetings)
  results.merge!(Recordings.process_recordings)
end.to_s[/\(\s*([\d.]*)\)/, 1]

filled_template = fill_template(results)

puts filled_template
