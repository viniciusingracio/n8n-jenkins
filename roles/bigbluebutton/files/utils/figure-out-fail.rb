#!/usr/bin/ruby
# encoding: UTF-8

require 'trollop'
require 'open4'
require 'fileutils'
require 'pp'
require 'logger'

opts = Trollop::options do
  opt :dry_run, "do not execute anything, just search", :type => :flag, :default => false
end

$dry_run = opts[:dry_run]
$logger = if $dry_run
        Logger.new(STDOUT)
    else
        Logger.new("/var/log/bigbluebutton/figure-out-fail.log")
    end
$logger.level = Logger::INFO

def exec_ret(*command)
  $logger.info "Executing: #{command.join(' ')}"
  return 0 if $dry_run
  IO.popen([*command, :err => [:child, :out]]) do |io|
    io.each_line do |line|
      $logger.info line.chomp
    end
  end
  $logger.info "Exit status: #{$?.exitstatus}"
  return $?.exitstatus
end

def check(file)
  File.exists?(file)
end

def remove(file)
  if check(file)
    FileUtils.rm_rf(file) if ! $dry_run
    $logger.info "Removing #{file}"
  end
end

def touch(file)
  if ! check(file)
    FileUtils.touch(file) if ! $dry_run
    $logger.info "Creating #{file}"
  end
end

def published_dir(format, record_id)
  "/var/bigbluebutton/published/#{format}/#{record_id}"
end

def unpublished_dir(format, record_id)
  "/var/bigbluebutton/unpublished/#{format}/#{record_id}"
end

def deleted_dir(format, record_id)
  "/var/bigbluebutton/deleted/#{format}/#{record_id}"
end

def presentation_published_dir(record_id)
  published_dir("presentation", record_id)
end

def presentation_unpublished_dir(record_id)
  unpublished_dir("presentation", record_id)
end

def presentation_deleted_dir(record_id)
  deleted_dir("presentation", record_id)
end

def presentation_video_published_dir(record_id)
  published_dir("presentation_video", record_id)
end

def presentation_video_unpublished_dir(record_id)
  unpublished_dir("presentation_video", record_id)
end

def presentation_video_deleted_dir(record_id)
  deleted_dir("presentation_video", record_id)
end

def process_dir(format, record_id)
  "/var/bigbluebutton/recording/process/#{format}/#{record_id}"
end

def publish_dir(format, record_id)
  "/var/bigbluebutton/recording/publish/#{format}/#{record_id}"
end

def presentation_process_dir(record_id)
  process_dir("presentation", record_id)
end

def presentation_publish_dir(record_id)
  publish_dir("presentation", record_id)
end

def presentation_video_process_dir(record_id)
  process_dir("presentation_video", record_id)
end

def presentation_video_publish_dir(record_id)
  publish_dir("presentation_video", record_id)
end

def presentation_recorder_process_dir(record_id)
  process_dir("presentation_recorder", record_id)
end

def presentation_recorder_video(record_id)
  "/var/bigbluebutton/recording/process/presentation_recorder/#{record_id}/video.mp4"
end

def archived_done(record_id)
  "/var/bigbluebutton/recording/status/archived/#{record_id}.done"
end

def sanity_done(record_id)
  "/var/bigbluebutton/recording/status/sanity/#{record_id}.done"
end

def archived_fail(record_id)
  "/var/bigbluebutton/recording/status/archived/#{record_id}.fail"
end

def sanity_fail(record_id)
  "/var/bigbluebutton/recording/status/sanity/#{record_id}.fail"
end

def processed_done(format, record_id)
  "/var/bigbluebutton/recording/status/processed/#{record_id}-#{format}.done"
end

def published_done(format, record_id)
  "/var/bigbluebutton/recording/status/published/#{record_id}-#{format}.done"
end

def presentation_processed_done(record_id)
  processed_done("presentation", record_id)
end

def presentation_published_done(record_id)
  published_done("presentation", record_id)
end

def presentation_video_processed_done(record_id)
  processed_done("presentation_video", record_id)
end

def presentation_video_published_done(record_id)
  published_done("presentation_video", record_id)
end

def presentation_recorder_processed_done(record_id)
  processed_done("presentation_recorder", record_id)
end

def processed_fail(format, record_id)
  "/var/bigbluebutton/recording/status/processed/#{record_id}-#{format}.fail"
end

def published_fail(format, record_id)
  "/var/bigbluebutton/recording/status/published/#{record_id}-#{format}.fail"
end

def presentation_processed_fail(record_id)
  processed_fail("presentation", record_id)
end

def presentation_published_fail(record_id)
  published_fail("presentation", record_id)
end

def presentation_video_processed_fail(record_id)
  processed_fail("presentation_video", record_id)
end

def presentation_video_published_fail(record_id)
  published_fail("presentation_video", record_id)
end

def presentation_recorder_processed_fail(record_id)
  processed_fail("presentation_recorder", record_id)
end

fail_set = []
Dir.glob("/var/bigbluebutton/recording/status/*/*.fail").each do |fail|
  match = /^.*\/(?<record_id>\w+-\d+)(?:-)?(?<format>\w+)?\.fail/.match fail
  next if match.nil?
  fail_set << match[:record_id]
end

fail_set.uniq.each do |record_id|
  record = {
    :id => record_id,
    :presentation_published_dir => presentation_published_dir(record_id),
    :presentation_unpublished_dir => presentation_unpublished_dir(record_id),
    :presentation_deleted_dir => presentation_deleted_dir(record_id),
    :presentation_video_published_dir => presentation_video_published_dir(record_id),
    :presentation_video_unpublished_dir => presentation_video_unpublished_dir(record_id),
    :presentation_video_deleted_dir => presentation_video_deleted_dir(record_id),
    :presentation_process_dir => presentation_process_dir(record_id),
    :presentation_publish_dir => presentation_publish_dir(record_id),
    :presentation_video_process_dir => presentation_video_process_dir(record_id),
    :presentation_video_publish_dir => presentation_video_publish_dir(record_id),
    :presentation_recorder_process_dir => presentation_recorder_process_dir(record_id),
    :presentation_recorder_video => presentation_recorder_video(record_id),
    :archived_done => archived_done(record_id),
    :sanity_done => sanity_done(record_id),
    :archived_fail => archived_fail(record_id),
    :sanity_fail => sanity_fail(record_id),
    :presentation_processed_done => presentation_processed_done(record_id),
    :presentation_published_done => presentation_published_done(record_id),
    :presentation_video_processed_done => presentation_video_processed_done(record_id),
    :presentation_video_published_done => presentation_video_published_done(record_id),
    :presentation_recorder_processed_done => presentation_recorder_processed_done(record_id),
    :presentation_processed_fail => presentation_processed_fail(record_id),
    :presentation_published_fail => presentation_published_fail(record_id),
    :presentation_video_processed_fail => presentation_video_processed_fail(record_id),
    :presentation_video_published_fail => presentation_video_published_fail(record_id),
    :presentation_recorder_processed_fail => presentation_recorder_processed_fail(record_id),
    :check_presentation_published_dir => check(presentation_published_dir(record_id)),
    :check_presentation_unpublished_dir => check(presentation_unpublished_dir(record_id)),
    :check_presentation_deleted_dir => check(presentation_deleted_dir(record_id)),
    :check_presentation_video_published_dir => check(presentation_video_published_dir(record_id)),
    :check_presentation_video_unpublished_dir => check(presentation_video_unpublished_dir(record_id)),
    :check_presentation_video_deleted_dir => check(presentation_video_deleted_dir(record_id)),
    :check_presentation_process_dir => check(presentation_process_dir(record_id)),
    :check_presentation_publish_dir => check(presentation_publish_dir(record_id)),
    :check_presentation_video_process_dir => check(presentation_video_process_dir(record_id)),
    :check_presentation_video_publish_dir => check(presentation_video_publish_dir(record_id)),
    :check_presentation_recorder_process_dir => check(presentation_recorder_process_dir(record_id)),
    :check_presentation_recorder_video => check(presentation_recorder_video(record_id)),
    :check_archived_done => check(archived_done(record_id)),
    :check_sanity_done => check(sanity_done(record_id)),
    :check_archived_fail => check(archived_fail(record_id)),
    :check_sanity_fail => check(sanity_fail(record_id)),
    :check_presentation_processed_done => check(presentation_processed_done(record_id)),
    :check_presentation_published_done => check(presentation_published_done(record_id)),
    :check_presentation_video_processed_done => check(presentation_video_processed_done(record_id)),
    :check_presentation_video_published_done => check(presentation_video_published_done(record_id)),
    :check_presentation_recorder_processed_done => check(presentation_recorder_processed_done(record_id)),
    :check_presentation_processed_fail => check(presentation_processed_fail(record_id)),
    :check_presentation_published_fail => check(presentation_published_fail(record_id)),
    :check_presentation_video_processed_fail => check(presentation_video_processed_fail(record_id)),
    :check_presentation_video_published_fail => check(presentation_video_published_fail(record_id)),
    :check_presentation_recorder_processed_fail => check(presentation_recorder_processed_fail(record_id))
  }

  $logger.info "Processing #{record_id}"

  if ( record[:check_presentation_video_processed_fail] || record[:check_presentation_video_published_fail] ) \
      && record[:check_presentation_published_done] \
      && record[:check_presentation_published_dir] \
      && (! record[:check_sanity_done] || record[:check_presentation_recorder_processed_fail] )

    $logger.info "Rebuild presentation_video for #{record_id}"
    remove record[:presentation_recorder_processed_fail]
    remove record[:presentation_recorder_processed_done]
    remove record[:presentation_recorder_process_dir]
    remove record[:presentation_video_processed_fail]
    remove record[:presentation_video_processed_done]
    remove record[:presentation_video_published_fail]
    remove record[:presentation_video_published_done]
    remove record[:presentation_video_published_dir]
    remove record[:presentation_processed_fail]
    remove record[:presentation_processed_done]
    remove record[:presentation_published_fail]
    touch record[:sanity_done]
  elsif ( record[:check_presentation_video_processed_fail] || record[:check_presentation_video_published_fail] ) \
      && record[:check_presentation_published_done] \
      && ( record[:check_presentation_deleted_dir] || record[:check_presentation_unpublished_dir] )

    $logger.info "Recording #{record_id} is not published"
    remove record[:presentation_recorder_processed_fail]
    remove record[:presentation_recorder_processed_done]
    remove record[:presentation_recorder_process_dir]
    remove record[:presentation_video_processed_fail]
    remove record[:presentation_video_processed_done]
    remove record[:presentation_video_published_fail]
    remove record[:presentation_video_published_done]
    remove record[:presentation_video_published_dir]
    remove record[:presentation_processed_fail]
    remove record[:sanity_done]
  elsif ! record[:check_presentation_published_done] \
      && ( record[:presentation_processed_fail] || record[:presentation_published_fail] )
    $logger.info "Rebuilding presentation for #{record_id}"
    command = [ "bbb-record", "--rebuild", record_id ]
    exec_ret(*command)
  else
    $logger.info "No match for #{record_id}"
    $logger.debug PP.pp record
  end

  if record[:check_presentation_published_done]
    remove record[:presentation_processed_fail]
    remove record[:presentation_published_fail]
  end
end
