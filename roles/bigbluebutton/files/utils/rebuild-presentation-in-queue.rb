#!/usr/bin/ruby

queue = Dir.glob("/var/bigbluebutton/recording/status/sanity/*.done").map{ |i| File.basename(i, ".done") } -
  Dir.glob("/var/bigbluebutton/published/presentation/*").map{ |i| File.basename(i) } -
  Dir.glob("/var/bigbluebutton/unpublished/presentation/*").map{ |i| File.basename(i) } -
  Dir.glob("/var/bigbluebutton/deleted/presentation/*").map{ |i| File.basename(i) } -
  `ps -eo args | grep '^ruby process/presentation.rb' | cut -d' ' -f4 | cut -d'-' -f1-2 | sort -u`.split() -
  `ps -eo args | grep '^ruby publish/presentation.rb' | cut -d' ' -f4 | cut -d'-' -f1-2 | sort -u`.split() -
  Dir.glob("/var/bigbluebutton/recording/status/processed/*-presentation.fail").map{ |i| File.basename(i, ".fail").gsub("-presentation", "") } -
  Dir.glob("/var/bigbluebutton/recording/status/published/*-presentation.fail").map{ |i| File.basename(i, ".fail").gsub("-presentation", "") }

queue.each do |record_id|
  puts `bbb-record --rebuild #{record_id}`
end
