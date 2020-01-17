#!/usr/bin/ruby
# encoding: UTF-8

#
# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
#
# Copyright (c) 2012 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the Free
# Software Foundation; either version 3.0 of the License, or (at your option)
# any later version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
# details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
#

require "google/cloud/storage"
require "google/cloud/speech"
require "trollop"
require "yaml"
require "fileutils"
require "json"
require "pp"
require File.expand_path("../../../lib/recordandplayback", __FILE__)

opts = Trollop::options do
  opt :meeting_id, "Record ID to transcribe", :type => String
  opt :force, "Force recording to be transcribed, no matter the matchers", :type => :flag, :default => false
end
meeting_id = opts[:meeting_id]

log_dir = "/var/log/bigbluebutton/transcribe"
FileUtils.mkdir_p log_dir
logger = Logger.new("#{log_dir}/#{meeting_id}.log")
logger.level = Logger::INFO
BigBlueButton.logger = logger

props = YAML::load(File.open(File.expand_path('../transcribe.yml', __FILE__)))
project_id = props["gcloud_project_id"]
bucket_name = props["gcloud_bucket_name"]
credentials_speech2text = props["gcloud_credentials_path_asr"]
credentials_storage = props["gcloud_credentials_path_storage"]
language_code = props["language_code"]
language_name = props["language_name"]
caption_duration = props["caption_duration"]
caption_paragraph_min_size = props["caption_paragraph_min_size"]

captions_code = language_code.gsub("-", "_")

published_dir = "/var/bigbluebutton/published/presentation/#{meeting_id}"
vtt_file = "#{published_dir}/caption_#{captions_code}.vtt"
captions_json = "#{published_dir}/captions.json"
speech_dir = "#{published_dir}/speech"
audio_file = "#{speech_dir}/recording.flac"

storage_file_name = "#{meeting_id}.flac"
storage_path = "gs://#{bucket_name}/#{storage_file_name}"

metadata_xml = "#{published_dir}/metadata.xml"
metadata = Nokogiri::XML(File.open(metadata_xml)) { |x| x.noblanks }
exit 0 if ! File.exists? metadata_xml

# Do not generate transcription if the metadata check doesn't match
match = false
props['matcher'].each do |item|
  node = metadata.at_xpath(item['xpath'])

  if ! node.nil? && node.text == item['value']
    match = true
    break
  end
end
exit 0 if ! ( match or opts[:force] )

BigBlueButton.logger.info("Generating #{language_code} transcription for #{meeting_id}")

if ! File.exist?(vtt_file)
  FileUtils.mkdir_p speech_dir
  if ! File.exist?(audio_file)
    raw_dir = "/var/bigbluebutton/recording/raw/#{meeting_id}"
    if Dir.exist?(raw_dir)
      BigBlueButton::EDL::Audio::FFMPEG_AFORMAT += ",volume=1.5,highpass=f=200,lowpass=f=2500"
      BigBlueButton::AudioProcessor.process(raw_dir, "#{speech_dir}/audio")
    elsif Dir.exist?(published_dir)
      command = ""
      if File.exist?("#{published_dir}/video/webcams.webm")
        command = "ffmpeg -i #{published_dir}/video/webcams.webm -vn -af 'volume=1.5, highpass=f=200, lowpass=f=2500, aformat=s16:48000' #{audio_file}"
      elsif File.exist?("#{published_dir}/video/webcams.mp4")
        command = "ffmpeg -i #{published_dir}/video/webcams.mp4 -vn -af 'volume=1.5, highpass=f=200, lowpass=f=2500, aformat=s16:48000' #{audio_file}"
      else
        raise "Can't find any file to extract the audio file"
      end
      BigBlueButton.execute(command)
    end
  end

  if File.exist?(audio_file)
    BigBlueButton.logger.info("Storing audio file as #{storage_file_name} at #{bucket_name}")
    storage = Google::Cloud::Storage.new project_id: project_id, credentials: credentials_storage
    bucket  = storage.bucket bucket_name
    file = bucket.create_file audio_file, storage_file_name

    BigBlueButton.logger.info("Transcribing #{storage_file_name} to #{language_code}")
    speech = Google::Cloud::Speech.new credentials: credentials_speech2text
    config = { encoding: :FLAC,
               sample_rate_hertz: 48_000,
               audio_channel_count: 2,
               enable_separate_recognition_per_channel: false,
               enable_word_time_offsets: true,
               enable_automatic_punctuation: true,
               language_code: language_code }
    audio = { uri: storage_path }
    operation = speech.long_running_recognize config, audio
    BigBlueButton.logger.info("Wait for it to be done")
    begin
      # default timeout was an hour, so it didn't work for long recordings
      # set timeout to 12 hours (last argument)
      operation.wait_until_done!(backoff_settings: Google::Gax::BackoffSettings.new(
        10 * Google::Gax::MILLIS_PER_SECOND,
        1.3,
        5 * 60 * Google::Gax::MILLIS_PER_SECOND,
        0,
        0,
        0,
        12 * 60 * 60 * Google::Gax::MILLIS_PER_SECOND
      ))
    rescue Exception => e
      BigBlueButton.logger.info "Something went wrong during wait_until_done!"
      BigBlueButton.logger.info e
    end
    raise if ! operation.done?
    BigBlueButton.logger.info("Done")
    raise operation.results.message if operation.error?
    results = operation.response.results
    File.open("#{speech_dir}/gcloud.out", 'w') { |file| PP.pp(results, file) }

    if ! results.empty?
      BigBlueButton.logger.info("Generating #{language_code} VTT file for #{meeting_id}")
      vtt = File.new(vtt_file, "w")
      vtt.write("WEBVTT\n")
      sequence_number = 0
      header = ""
      start = 0.0
      last_stop = 0.0
      content = []
      paragraph_break = false
      new_paragraph = "\nNOTE MCONF_CUE_META {\"paragraph\":\"true\"}\n"
      paragraph_size = 0

      results.each do |result|
        alternative = result.alternatives.first
        alternative.words.each_with_index do |word, index|
          if content.empty?
            sequence_number += 1
            if paragraph_break
              header = "#{new_paragraph}\n#{sequence_number}"
            else
              header = "#{sequence_number}"
            end
            # avoid the first word to be assigned at 0.0 seconds
            # avoid start to be less or equal to last stop
            start = [ word.start_time.seconds + word.start_time.nanos / 1_000_000_000.0, last_stop + 0.1 ].max
          end
          # avoid stop to be less or equal to start
          stop = [ word.end_time.seconds + word.end_time.nanos / 1_000_000_000.0, start + 0.1 ].max

          content << word.word
          paragraph_size = paragraph_size + word.word.length + 1
          punct = word.word =~ /[.]/

          duration_break = stop - start > caption_duration
          end_break = index == alternative.words.length - 1
          paragraph_break = ! punct.nil? && paragraph_size > caption_paragraph_min_size
          paragraph_size = 0 if paragraph_break

          if duration_break || end_break || paragraph_break
            time = "#{Time.at(start).utc.strftime("%T.%L")} --> #{Time.at(stop).utc.strftime("%T.%L")}"
            vtt.write("\n#{header}\n#{time}\n#{content.join(" ")}\n")
            content = []
            last_stop = stop
          end
        end
      end
      vtt.close

      BigBlueButton.logger.info("Editing #{meeting_id} captions JSON file")
      old_captions = []
      if File.exists? captions_json
        old_captions = JSON.parse(File.read(captions_json))
      end
      old_captions.reject! { |item| item["locale"] == captions_code }
      captions = { "localeName" => language_name, "locale" => captions_code }
      old_captions << captions
      File.open(captions_json, "w") do |f|
        f.write(old_captions.to_json)
      end
    else
      BigBlueButton.logger.error("Could not transcribe #{storage_file_name}")
    end
    BigBlueButton.logger.info("Deleting audio file #{storage_file_name} from #{bucket_name}")
    file.delete
  else
    BigBlueButton.logger.warn("Could not find #{audio_file}")
  end
  BigBlueButton.logger.info("Deleting #{speech_dir}")
  FileUtils.remove_dir(speech_dir)
else
  BigBlueButton.logger.warn("Caption file for #{captions_code} already exists at #{meeting_id}")
end

exit 0
