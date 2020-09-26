#!/usr/bin/ruby

require 'erb'
require 'docker'
require 'json'
require 'benchmark'

rec_stats = {}

time = Benchmark.measure do
  rec_formats = Dir.glob("/usr/local/bigbluebutton/core/scripts/process/*.rb").map{ |i| File.basename(i, ".rb") }
  rec_formats << "presentation_recorder" if rec_formats.include? "presentation_video"
  rec_stats = {
    :archived => Dir.glob("/var/bigbluebutton/recording/status/archived/*.done").map{ |i| File.basename(i, ".done") },
    :sanity => Dir.glob("/var/bigbluebutton/recording/status/sanity/*.done").map{ |i| File.basename(i, ".done") },
    :processed => {},
    :archived_fail => Dir.glob("/var/bigbluebutton/recording/status/archived/*.fail").map{ |i| File.basename(i, ".fail") },
    :sanity_fail => Dir.glob("/var/bigbluebutton/recording/status/sanity/*.fail").map{ |i| File.basename(i, ".fail") },
    :processed_fail => {},
    :published_fail => {}
  }
  rec_formats.each do |format|
    rec_stats[:processed][format.to_sym] = Dir.glob("/var/bigbluebutton/recording/status/processed/*-#{format}.done").map{ |i| File.basename(i, ".done").gsub("-#{format}", "") }
    rec_stats[:processed_fail][format.to_sym] = Dir.glob("/var/bigbluebutton/recording/status/processed/*-#{format}.fail").map{ |i| File.basename(i, ".fail").gsub("-#{format}", "") }
    rec_stats[:published_fail][format.to_sym] = Dir.glob("/var/bigbluebutton/recording/status/published/*-#{format}.fail").map{ |i| File.basename(i, ".fail").gsub("-#{format}", "") }
  end

  [ :published, :unpublished, :deleted ].each do |state|
    rec_stats[state] = {}
    rec_formats.each do |format|
      rec_stats[state][format.to_sym] = Dir.glob("/var/bigbluebutton/#{state.to_s}/#{format}/*").map{ |i| File.basename(i) }
    end
  end

  [ :processing, :publishing, :queued ].each do |state|
    rec_stats[state] = {}
    rec_formats.each do |format|
      case state
      when :processing
        rec_stats[state][format.to_sym] = `ps -eo args | grep '^ruby process/#{format}.rb' | cut -d' ' -f4 | cut -d'-' -f1-2 | sort -u`.split()
      when :publishing
        rec_stats[state][format.to_sym] = `ps -eo args | grep '^ruby publish/#{format}.rb' | cut -d' ' -f4 | cut -d'-' -f1-2 | sort -u`.split()
      else
        rec_stats[state][format.to_sym] = []
      end
    end
  end

  if rec_formats.include? "presentation_recorder"
    all_containers = Docker::Container.all(:all => true)
    rec_stats[:processing][:presentation_recorder] = all_containers.select{ |container| container.info["Names"].first.start_with?("/record_") and container.info["State"] == "running" }.map{ |container| container.info["Names"].first.gsub(/^\/record_/, "") }
  end

  rec_stats[:queued][:presentation] = rec_stats[:sanity] -
    rec_stats[:published][:presentation] -
    rec_stats[:unpublished][:presentation] -
    rec_stats[:deleted][:presentation] -
    rec_stats[:processing][:presentation] -
    rec_stats[:publishing][:presentation] -
    rec_stats[:processed_fail][:presentation] -
    rec_stats[:published_fail][:presentation] if rec_formats.include? "presentation"

  if rec_formats.include? "presentation_video"
    rec_stats[:queued][:presentation_video] = ( rec_stats[:sanity] & rec_stats[:published][:presentation] ) -
      rec_stats[:processing][:presentation_recorder] -
      rec_stats[:processed][:presentation_recorder] -
      rec_stats[:processing][:presentation_video] -
      rec_stats[:publishing][:presentation_video] -
      rec_stats[:published_fail][:presentation_video]

    rec_stats[:processed_fail][:presentation_video] = rec_stats[:processed_fail][:presentation_video] -
      rec_stats[:queued][:presentation_video] -
      rec_stats[:processing][:presentation_recorder]
  end
end.to_s[/\(\s*([\d.]*)\)/, 1]

def count_elements(parent, hash)
  hash.each do |key, value|
    if value.is_a?(Hash)
      count_elements(key, value)
    elsif value.is_a?(Array)
      hash[key] = value.length
    end
  end
end

# puts JSON.pretty_generate(count_elements(nil, rec_stats))
# exit 0

template =
<<~HEREDOC
  # HELP bbb_recordings_count The number of recordings for each state and format
  # TYPE bbb_recordings_count gauge
<% count_elements(nil, rec_stats).each do |state, v1| -%>
<% if v1.is_a?(Hash) -%>
<% v1.each do |format, v2| -%>
  bbb_recordings_count{state="<%= state %>",format="<%= format %>"} <%= v2 %>
<% end -%>
<% else -%>
  bbb_recordings_count{state="<%= state %>"} <%= v1 %>
<% end -%>
<% end -%>

  # HELP bbb_recordings_count_time The response time for fetching the recordings data
  # TYPE bbb_recordings_count_time gauge
  bbb_recordings_count_time <%= time %>
HEREDOC

puts ERB.new(template, nil, "-").result
