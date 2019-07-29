# encoding: UTF-8

require 'open4'

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

Dir.glob("/var/bigbluebutton/recording/status/**/*-presentation.fail").each do |filename|
  match = /^.*\/(?<record_id>\w+-\d+)-(?<format>\w+)\.fail/.match filename
  next if match.nil?
  record_id = match[:record_id]
  command = [ "bbb-record", "--rebuild", record_id ]
  exec_ret(*command)
end
