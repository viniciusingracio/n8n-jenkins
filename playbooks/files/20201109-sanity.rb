#!/usr/bin/ruby
# encoding: UTF-8
#
# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
#
# Copyright (c) 2012 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under the
# terms of the GNU Lesser General Public License as published by the Free Software
# Foundation; either version 3.0 of the License, or (at your option) any later
# version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
#


require '../lib/recordandplayback'
require 'logger'
require 'trollop'
require 'yaml'
require "nokogiri"
require "redis"
require "fileutils"

# This script lives in scripts/archive/steps while bigbluebutton.yml lives in scripts/
props = YAML::load(File.open('bigbluebutton.yml'))
log_dir = props['log_dir']
audio_dir = props['raw_audio_src']
recording_dir = props['recording_dir']
raw_archive_dir = "#{recording_dir}/raw"
redis_host = props['redis_host']
redis_port = props['redis_port']
redis_password = props['redis_password']

opts = Trollop::options do
  opt :meeting_id, "Meeting id to archive", type: :string
  opt :break_timestamp, "Chapter break end timestamp", type: :string
end
Trollop::die :meeting_id, "must be provided" if opts[:meeting_id].nil?

meeting_id = opts[:meeting_id]
break_timestamp = opts[:break_timestamp]


BigBlueButton.logger = Logger.new("#{log_dir}/sanity.log", 'daily' )
logger = BigBlueButton.logger

def check_events_xml(raw_dir,meeting_id)
  filepath = "#{raw_dir}/#{meeting_id}/events.xml"
  raise Exception,  "Events file doesn't exists." if not File.exists?(filepath)
  bad_doc = Nokogiri::XML(File.open(filepath)) { |config| config.options = Nokogiri::XML::ParseOptions::STRICT }
end

def repair_red5_ser(directory)
  cp="/usr/share/red5/red5-server.jar:/usr/share/red5/lib/*"
  if File.directory?(directory)
    FileUtils.cd(directory) do

      BigBlueButton.logger.info("Repairing red5 serialized streams")
      Dir.glob("*.flv.ser").each do |ser|
        BigBlueButton.logger.info("Repairing #{ser}")
        ret = BigBlueButton.exec_ret('java', '-cp', cp, 'org.red5.io.flv.impl.FLVWriter', ser, '0', '7')
        if ret != 0
          BigBlueButton.logger.warn("Failed to repair #{ser}")
          next
        end

        BigBlueButton.logger.info("Cleaning up .flv.ser and .flv.info files")
        FileUtils.rm_f(ser)
        FileUtils.rm_f("#{ser[0..-5]}.info")
      end
    end
  end
end

# Check if ogg file has corrupted bytes at the beginning and remove them
# Valid files start with "Ogg"
def checkAndFixOggCorruptedInitialBytes(file)
  tail = ['tail', '-c']
  # open file as binary, read X bytes and immediately closes
  oggIndex = File.open(file, 'rb') { |io| io.read(2048) }.index("Ogg")
  if oggIndex && oggIndex > 0
    # file does not start with Ogg, remove first oggIndex+1 bytes
    BigBlueButton.logger.info("#{oggIndex+1} Corrupted bytes found before Ogg string, fixing...")
    tail_cmd = [*tail]
    tail_cmd += ["+#{oggIndex+1}", file]
    output = "fixed_#{file}"
    ret = BigBlueButton.exec_redirect_ret(output,*tail_cmd)
    if ret != 0
      BigBlueButton.logger.warn("Failed to fix initial bytes of #{file}")
      FileUtils.rm_f(output)
      return -1
    end
    BigBlueButton.logger.info("Fixed bytes, cleaning up original file")
    # keep original ogg file, so we have the possibility to inspect it later on
    FileUtils.mv(file, "#{file}.orig")
    FileUtils.mv(output, file)
    return 0
  else
    return 1
  end
end

def remux_files(directory)
  ffmpeg = ['ffmpeg', '-y', '-v', 'warning', '-nostats', '-max_error_rate', '1.0']
  if File.directory?(directory)
    FileUtils.cd(directory) do

      BigBlueButton.logger.info("Remuxing audio files to fix corrupted streams")
      Dir.glob("*.opus").each do |audio|
        BigBlueButton.logger.info("Remuxing #{audio}")
        ffmpeg_cmd = [*ffmpeg]
        output = "remuxed_#{audio}"
        ffmpeg_cmd += ['-i', audio, '-c', 'copy', '-map', '0', output]
        ret = BigBlueButton.exec_ret(*ffmpeg_cmd)
        if ret != 0
          if File.size(audio) < 1000
            BigBlueButton.logger.warn("File size is less than 1000 bytes, probably empty file, will be ignored #{audio}")
            next
          end
          fixOggRet = checkAndFixOggCorruptedInitialBytes(audio)
          if fixOggRet == 0
            # file had corrupted initial bytes and is now fixed, remux again
            ret = BigBlueButton.exec_ret(*ffmpeg_cmd)
            if ret != 0
              FileUtils.rm_f(output)
              raise Exception, "Failed to remux #{audio} after fixing invalid bytes"
            end
          else
            FileUtils.rm_f(output)
            raise Exception, "Failed to remux #{audio}"
          end
        end

        BigBlueButton.logger.info("Remuxed, cleaning up original file")
        FileUtils.rm_f(audio)
        FileUtils.mv(output, audio)
      end
    end
  end
end


# Determine the filenames for the done and fail files
if !break_timestamp.nil?
  done_base = "#{meeting_id}-#{break_timestamp}"
else
  done_base = meeting_id
end

begin
  logger.info("Starting sanity check for recording #{meeting_id}")
  if !break_timestamp.nil?
    logger.info("Break timestamp is #{break_timestamp}")
  end

  logger.info("Checking events.xml")
  check_events_xml(raw_archive_dir,meeting_id)

  logger.info("Repairing webcam videos")
  repair_red5_ser("#{raw_archive_dir}/#{meeting_id}/video/#{meeting_id}")

  logger.info("Repairing deskshare videos")
  repair_red5_ser("#{raw_archive_dir}/#{meeting_id}/deskshare")

  logger.info("Repairing audio files")
  remux_files("#{raw_archive_dir}/#{meeting_id}/audio")

  if break_timestamp.nil?
    # Either this recording isn't segmented, or we are working on the last
    # segment, so go ahead and clean up all the redis data.
    logger.info("Deleting keys")
    redis = BigBlueButton::RedisWrapper.new(redis_host, redis_port, redis_password)
    events_archiver = BigBlueButton::RedisEventsArchiver.new(redis)
    events_archiver.delete_events(meeting_id)
  end
rescue Exception => e
  BigBlueButton.logger.error("error in sanity check: " + e.message)
  BigBlueButton.logger.error(e.backtrace.join("\n"))
  exit 1
end
