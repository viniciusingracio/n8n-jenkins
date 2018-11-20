require 'nokogiri'
require 'open4'
require 'pp'
require 'json'

output = ""
command = "/opt/freeswitch/bin/fs_cli -x 'show channels as xml'"
Open4::popen4(command) do |pid, stdin, stdout, stderr|
  output = stdout.readlines
end

data = []

doc = Nokogiri::XML(output.join(), nil, "UTF-8") { |x| x.noblanks }
doc.xpath("/result/row").each do |row|
  name = row.at_xpath("cid_name").text
  next if /^GLOBAL_AUDIO.*/.match(name)

  uuid = row.at_xpath("uuid").text
  webrtc = row.at_xpath("secure").text.length != 0
  ip = row.at_xpath("ip_addr").text

  stats_query = {
    'command' => 'mediaStats',
    'data' => {
      'uuid' => uuid
    }
  }
  command = "/opt/freeswitch/bin/fs_cli -x 'json #{JSON.dump(stats_query)}'"
  Open4::popen4(command) do |pid, stdin, stdout, stderr|
    output = stdout.readlines
  end
  response = JSON.load(output.join())

  quality = response["response"]["audio"]["in_quality_percentage"]

  data << {
    :uuid => uuid,
    :name => name,
    :webrtc => webrtc,
    :ip => ip,
    :quality => quality
  }
end

avg = 1.0
webrtc = 1.0
if ! data.empty?
  avg = ( data.inject(0){ |sum, el| sum + el[:quality] }.to_f / data.size ) / 100
  webrtc = ( data.select{ |el| el[:webrtc] }.size.to_f / data.size )
end

puts "quality: #{avg.round(2)}, webrtc: #{webrtc.round(2)}, count: #{data.size}"
