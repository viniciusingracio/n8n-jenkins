# encoding: UTF-8

require 'json'
require 'open4'
require 'fileutils'

FFPROBE = ['/usr/bin/ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_format', '-show_streams', '-count_frames']
command = FFPROBE + [ "-select_streams", "v", "-show_frames", "-show_entries", "frame=pkt_pts_time" ]

universe = 0
problematic = 0
to_rebuild = []

def exec_ret(*command)
  puts "Executing: #{command.join(' ')}"
  IO.popen([*command, :err => [:child, :out]]) do |io|
    io.each_line do |line|
      puts line.chomp
    end
  end
  puts "Exit status: #{$?.exitstatus}"
  return $?.exitstatus
end

Dir.glob("/var/bigbluebutton/recording/raw/**/medium-v_[0-9]*-[0-9]*.mkv").each do |filename|
  match = /^\/var\/bigbluebutton\/recording\/raw\/(?<record_id>\w+-\d+)\/.*/.match filename
  next if match.nil?
  record_id = match[:record_id]

  IO.popen([*command, filename]) do |probe|
    info = nil
    begin
      info = JSON.parse(probe.read, :symbolize_names => true)
    rescue Exception => e
      puts "Failed to get video info from #{filename}"
    end

    next if info.nil? || info[:streams].nil? || info[:frames].nil?

    begin
      universe += 1
      interval = 5
      max_frames_in_interval = 15 * interval * 10
      info[:frames].collect! { |frame| frame[:pkt_pts_time].to_f }
      info[:frames][0..-(max_frames_in_interval+1)].each_with_index do |frame, index|
        second_frame = info[:frames][index + max_frames_in_interval]
        diff = second_frame - frame
        if diff < interval.to_f
          problematic += 1
          puts "Difference between frame #{index} at #{frame}s and frame #{index+max_frames_in_interval} at #{second_frame} is #{diff} (more than #{max_frames_in_interval} frames in #{interval} seconds), filename #{filename}"
          FileUtils.cp(filename, "#{filename}.orig") if ! File.exists?("#{filename}.orig")
          [ [ "ffmpeg", "-y", "-nostats", "-i", "#{filename}.orig", "-filter:v", "setpts=N/(15*TB)", filename ],
            [ "chown", "-R", "tomcat7:tomcat7", "#{File.dirname(filename)}" ] ].each { |command| exec_ret(*command) }
          to_rebuild << record_id
          break
        end
      end
    rescue Exception => e
      puts "Something went wrong while processing file #{filename}"
      puts e
    end
  end
end

to_rebuild.each do |record_id|
  command = [ "bbb-record", "--rebuild", record_id ]
  exec_ret(*command)
end

puts "Total of mkv inspected: #{universe}"
puts "Total of issues found: #{problematic}"
puts "Total of recordings reprocessed: #{to_rebuild.length}"

