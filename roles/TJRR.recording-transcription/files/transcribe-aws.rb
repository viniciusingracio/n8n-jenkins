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

require 'aws-sdk'
require "trollop"
require "yaml"
require "fileutils"
require "json"
require "pp"
require File.expand_path("../../../lib/recordandplayback", __FILE__)

opts = Trollop::options do
  opt :meeting_id, "Record ID to transcribe", :type => String
  opt :force, "Force recording to be transcribed, no matter the matchers", :type => :flag, :default => false
  opt :stdout, "Log to stdout", :type => :flag, :default => false
end
meeting_id = opts[:meeting_id]

log_dir = "/var/log/bigbluebutton/transcribe"
FileUtils.mkdir_p log_dir

if ! opts[:stdout]
  logger = Logger.new("#{log_dir}/#{meeting_id}.log")
  logger.level = Logger::INFO
  BigBlueButton.logger = logger
end

props = YAML::load(File.open(File.expand_path('../transcribe.yml', __FILE__)))
aws_key = props["aws_key"]
aws_secret = props["aws_secret"]
aws_region = props["aws_region"]
bucket_name = props["aws_bucket_name"]
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
storage_path = "s3://#{bucket_name}/#{storage_file_name}"

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
      BigBlueButton::AudioProcessor.process(raw_dir, "#{speech_dir}/audio")
    elsif Dir.exist?(published_dir)
      command = ""
      if File.exist?("#{published_dir}/video/webcams.webm")
        command = "ffmpeg -i #{published_dir}/video/webcams.webm -vn -af aformat=s16:48000 #{audio_file}"
      elsif File.exist?("#{published_dir}/video/webcams.mp4")
        command = "ffmpeg -i #{published_dir}/video/webcams.mp4 -vn -af aformat=s16:48000 #{audio_file}"
      else
        raise "Can't find any file to extract the audio file"
      end
      BigBlueButton.execute(command)
    end
  end

  if File.exist?(audio_file)
    credentials = Aws::Credentials.new(aws_key, aws_secret)
    s3_client = Aws::S3::Client.new(
      credentials: credentials,
      region: aws_region
    )
    s3_resource = Aws::S3::Resource.new(
      client: s3_client
    )

    BigBlueButton.logger.info("Storing audio file as #{storage_file_name} at #{bucket_name}")
    opts = { :acl => "private" }
    obj = s3_resource.bucket(bucket_name).object(storage_file_name)
    obj.upload_file(audio_file, opts)

    BigBlueButton.logger.info("Transcribing #{storage_file_name} to #{language_code}")
    transcribe_client = Aws::TranscribeService::Client.new(
      credentials: credentials,
      region: aws_region
    )

    # make sure there's no naming conflict
    resp = transcribe_client.list_transcription_jobs({
      job_name_contains: meeting_id,
      max_results: 1,
    })
    if resp.transcription_job_summaries.length > 0
      transcribe_client.delete_transcription_job({
        transcription_job_name: meeting_id,
      })
    end

    resp = transcribe_client.start_transcription_job({
      transcription_job_name: meeting_id,
      language_code: language_code,
      media_sample_rate_hertz: 48000,
      media_format: "flac",
      media: {
        media_file_uri: storage_path,
      },
      output_bucket_name: bucket_name,
      settings: {
        show_speaker_labels: true,
        max_speaker_labels: 10 # must be between 2 and 10
      },
    })

    BigBlueButton.logger.info("Wait for it to be done")

    resp = nil
    loop do
      resp = transcribe_client.get_transcription_job({
        transcription_job_name: meeting_id,
      })
      BigBlueButton.logger.info(resp.transcription_job.transcription_job_status)
      break if resp.transcription_job.transcription_job_status != "IN_PROGRESS"
      sleep 15
    end
    BigBlueButton.logger.info("Done")
    raise "Job stopped with status #{resp.transcription_job.transcription_job_status}" if resp.transcription_job.transcription_job_status != "COMPLETED"

    obj = s3_resource.bucket(bucket_name).object("#{meeting_id}.json")
    raise "Transcript file does not exist" if ! obj.exists?
    json = ""
    begin
      io = StringIO.new
      obj.get({ response_target: io })
      json = io.readlines.map{ |line| line.strip }.join("")
    rescue Exception => e
      BigBlueButton.logger.error "Failed to load transcript file: #{e.message}"
      raise e
    end
    results = JSON.parse(json, { :symbolize_names => true })[:results]

    if ! results.empty?
      BigBlueButton.logger.info("Generating #{language_code} VTT file for #{meeting_id}")
      vtt = File.new(vtt_file, "w")
      vtt.write("WEBVTT\n\n")
      sequence_number = 0
      header = ""
      start = 0.0
      stop = 0.0
      content = []
      paragraph_size = 0

      change_speaker = {}
      current_speaker = nil
      results[:speaker_labels][:segments].each do |segment|
        segment[:items].each do |item|
          if item[:speaker_label] != current_speaker
            current_speaker = item[:speaker_label]
            change_speaker[item[:start_time]] = current_speaker
          end
        end
      end

      new_speaker = nil
      results[:items].each_with_index do |result, index|
        alternative = result[:alternatives].first
        paragraph_break = false
        if result[:type] == "punctuation"
          content.last << alternative[:content]
          paragraph_break = paragraph_size > caption_paragraph_min_size if alternative[:content] == "."
        elsif result[:type] == "pronunciation"
          # avoid the first word to be assigned at 0.0 seconds
          # avoid start to be less or equal to last stop
          start = [ result[:start_time].to_f, stop + 0.1 ].max if content.empty?
          new_speaker = change_speaker[result[:start_time]] if change_speaker.key?(result[:start_time])
          content << alternative[:content]
          paragraph_size += 1
          # avoid stop to be less or equal to start
          stop = [ result[:end_time].to_f, start + 0.1 ].max
        end

        last_word = index == results[:items].length - 1
        if ! last_word
          next_result = results[:items][index + 1]
          change_speaker_next = change_speaker.key?(next_result[:start_time])
          if ! paragraph_break && ! change_speaker_next
            next if next_result[:type] == "punctuation"
            next if next_result[:end_time].to_f - start <= caption_duration
          end
        end

        sequence_number += 1
        time = "#{Time.at(start).utc.strftime("%T.%L")} --> #{Time.at(stop).utc.strftime("%T.%L")}"
        message = ""
        if ! new_speaker.nil?
          message << "NOTE MCONF_CUE_META {\"voice\":\"#{new_speaker}\"}\n\n"
          new_speaker = nil
        end
        message << "#{sequence_number}\n"
        message << "#{time}\n"
        message << "#{content.join(" ")}\n\n"
        if ! last_word && paragraph_break
          message << "NOTE MCONF_CUE_META {\"paragraph\":\"true\"}\n\n"
          paragraph_size = 0
        end

        vtt.write(message)
        content = []
      end
      vtt.close

      BigBlueButton.logger.info("Editing #{meeting_id} captions JSON file")
      old_captions = []
      if File.exists? captions_json
        old_captions = JSON.parse(File.read(captions_json))
      end
      captions = { "localeName" => language_name, "locale" => captions_code }
      old_captions << captions
      File.open(captions_json, "w") do |f|
        f.write(old_captions.to_json)
      end
    else
      BigBlueButton.logger.error("Could not transcribe #{storage_file_name}")
    end
    BigBlueButton.logger.info("Deleting audio file #{storage_file_name} from #{bucket_name}")
    s3_resource.bucket(bucket_name).delete_objects(
      {
        delete: {
          objects: [
            { key: "#{meeting_id}.json" },
            { key: storage_file_name }
          ]
        }
      }
    )

    BigBlueButton.logger.info("Deleting transcription job for #{meeting_id}")
    transcribe_client.delete_transcription_job({
      transcription_job_name: meeting_id,
    })
  else
    BigBlueButton.logger.warn("Could not find #{audio_file}")
  end
  BigBlueButton.logger.info("Deleting #{speech_dir}")
  FileUtils.remove_dir(speech_dir)
else
  BigBlueButton.logger.warn("Caption file for #{captions_code} already exists at #{meeting_id}")
end

exit 0
