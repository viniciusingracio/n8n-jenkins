require 'open4'
require 'pp'
require 'json'
require 'nokogiri'
require 'redis'
require 'yaml'
require '/usr/local/bigbluebutton/core/scripts/utils/monitoring-utils.rb'

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

  row[:stats] = response[:response][:audio]
end

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
    # puts PP.pp meeting

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

props = YAML::load(File.open('/usr/local/bigbluebutton/core/scripts/bigbluebutton.yml'))
redis = Redis.new(:host => props['redis_host'], :port => props['redis_port'])
output = redis.get("participants-monitoring-cache")

regexp_checks = [ /_bytes$/, /_count$/, /_total$/ ]
if ! output.nil?
  prev_data = JSON.parse(output, symbolize_names: true)
  participants.each do |participant|
    next if participant[:audio].empty? or participant[:audio][:stats].empty?
    prev_participant = prev_data.select { |row| row[:audio][:uuid] == participant[:audio][:uuid] }.first
    next if prev_participant.nil? or prev_participant[:audio].empty? or prev_participant[:audio][:stats].empty?

    participant[:audio][:stats].keys.select { |key| regexp_checks.any? { |rgx| key.to_s =~ rgx } }.each do |key|
      next if ! prev_participant[:audio][:stats].has_key?(key)

      participant[:audio][:stats]["#{key.to_s}_diff".to_sym] = participant[:audio][:stats][key] - prev_participant[:audio][:stats][key]
    end

    stats = participant[:audio][:stats]

    if stats.has_key?(:in_skip_packet_count_diff) and stats.has_key?(:in_packet_count_diff) and (stats[:in_skip_packet_count_diff] + stats[:in_packet_count_diff] > 0)
      stats[:in_skip_packet_count_diff_rate] = stats[:in_skip_packet_count_diff] / (stats[:in_skip_packet_count_diff] + stats[:in_packet_count_diff]).to_f
    end

    if stats.has_key?(:out_skip_packet_count_diff) and stats.has_key?(:out_packet_count_diff) and (stats[:out_skip_packet_count_diff] + stats[:out_packet_count_diff] > 0)
      stats[:out_skip_packet_count_diff_rate] = stats[:out_skip_packet_count_diff] / (stats[:out_skip_packet_count_diff] + stats[:out_packet_count_diff]).to_f
    end
 
    if stats.has_key?(:in_flaw_total_diff) and stats.has_key?(:in_packet_count_diff) and (stats[:in_flaw_total_diff] + stats[:in_packet_count_diff] > 0)
      stats[:in_flaw_total_diff_rate] = stats[:in_flaw_total_diff] / (stats[:in_flaw_total_diff] + stats[:in_packet_count_diff]).to_f
    end
  end
end

# puts PP.pp participants

redis.set("participants-monitoring-cache", participants.to_json)

participants.map! do |participant|
  r = {
    "name" => participant[:meeting][:meetingName],
    "user" => participant[:fullName],
    "audio" => participant[:hasJoinedVoice].downcase == "true"
  }
  if ! participant[:audio].empty?
    r["quality"] = participant[:audio][:stats][:in_quality_percentage]
    r["in_skip_rate"] = (participant[:audio][:stats][:in_skip_packet_count_diff_rate] * 100).round() if participant[:audio][:stats].has_key?(:in_skip_packet_count_diff_rate)
    r["out_skip_rate"] = (participant[:audio][:stats][:out_skip_packet_count_diff_rate] * 100).round() if participant[:audio][:stats].has_key?(:out_skip_packet_count_diff_rate)
    r["flaw_rate"] = (participant[:audio][:stats][:in_flaw_total_diff_rate] * 100).round() if participant[:audio][:stats].has_key?(:in_flaw_total_diff_rate)
  end
  r
end

puts participants.to_json.gsub("},", "},\n ")
