require 'open4'
require 'json'
require 'date'

=begin
add the following lines to crontab:

* * * * * sleep 30; ruby audio-stats.rb | curl -H "Content-Type: multipart/form-data" -X POST -d @- http://localhost:9880/audio_stats
* * * * * sleep 60; ruby audio-stats.rb | curl -H "Content-Type: multipart/form-data" -X POST -d @- http://localhost:9880/audio_stats
=end

output = ""
command = "/opt/freeswitch/bin/fs_cli -x 'show channels as json'"
Open4::popen4(command) do |pid, stdin, stdout, stderr|
  output = stdout.readlines
end

voice_data = JSON.parse(output.join(), symbolize_names: true)[:rows] || []

voice_data.each do |row|
  row[:listen_only] = ! /^GLOBAL_AUDIO.*/.match(row[:cid_name]).nil?
  m = /(?<user_id>.*)_\d+-bbbID-(?<user_name>.*)/.match(row[:cid_name])
  if ! m.nil?
    row[:user_id] = m["user_id"]
    row[:full_name] = m["user_name"]
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

puts voice_data.to_json
