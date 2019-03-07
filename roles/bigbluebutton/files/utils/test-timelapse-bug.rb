# encoding: UTF-8

require 'json'
require 'open4'

FFPROBE = ['/usr/bin/ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_format', '-show_streams', '-count_frames']
command = FFPROBE + [ "-select_streams", "v", "-show_frames", "-show_entries", "frame=pkt_pts_time" ]

Dir.glob("/var/bigbluebutton/recording/raw/**/medium-v_[0-9]*-[0-9]*.mkv").each do |filename|
  IO.popen([*command, filename]) do |probe|
    info = nil
    begin
      info = JSON.parse(probe.read, :symbolize_names => true)
    rescue Exception => e
      puts "Failed to get video info from #{filename}"
    end

    next if info.nil? || info[:streams].nil? || info[:frames].nil?

    interval = 5
    max_frames_in_interval = 15 * interval * 10
    info[:frames].collect! { |frame| frame[:pkt_pts_time].to_f }
    info[:frames][0..-(max_frames_in_interval+1)].each_with_index do |frame, index|
      second_frame = info[:frames][index + max_frames_in_interval]
      diff = second_frame - frame
      if diff < interval.to_f
        puts "Difference between frame #{index} at #{frame}s and frame #{index+max_frames_in_interval} at #{second_frame} is #{diff} (more than #{max_frames_in_interval} frames in #{interval} seconds), filename #{filename}"
        break
      end
    end
  end
end
