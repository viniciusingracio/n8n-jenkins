#!/usr/bin/ruby
# encoding: UTF-8

require 'trollop'
require 'date'
require 'fileutils'
require 'nokogiri'
require 'logger'

opts = Trollop::options do
  opt :record_id, "Record ID", :type => String, :required => true
  opt :process_number, "Process Number", :type => String, :required => true
  opt :dry_run, "Do not execute anything, just search", :type => :flag, :default => false
end

logger = if opts[:dry_run]
        Logger.new(STDOUT)
    else
        Logger.new("/var/log/bigbluebutton/move-process.log")
    end
logger.level = Logger::INFO

record_id = opts[:record_id]
process_number = opts[:process_number]

filename = "/var/bigbluebutton/published/presentation/#{record_id}/metadata.xml"
if ! File.exists? filename
  logger.info "Couldn't find metadata for #{record_id}"
  exit 1
end

doc = Nokogiri::XML(File.open(filename)) { |x| x.noblanks }

xml_node = doc.at_xpath("/recording/meta/mconflb-institution-name")
if xml_node.nil?
    logger.warn "Couldn't find mconflb-institution-name for #{record_id}"
else
    xml_node.content = "Projudi"
end

xml_node = doc.at_xpath("/recording/meta/mconflb-institution")
if xml_node.nil?
    logger.warn "Couldn't find mconflb-institution for #{record_id}"
else
    xml_node.content = "4"
end

[ "/recording/meta/meetingId", "/recording/meta/meetingName", "/recording/meeting/@externalId", "/recording/meeting/@name"].each do |xpath|
    xml_node = doc.at_xpath(xpath)
    if xml_node.nil?
        logger.warn "Couldn't find #{xpath} for #{record_id}"
    else
        xml_node.content = process_number
    end
end

logger.info "#{record_id} => #{process_number} (#{filename})"

if opts[:dry_run]
    logger.info "Updated metadata:\n#{doc.to_xml(:indent => 2)}"
else
    datetime = DateTime.parse(File.mtime(filename).to_s).strftime("%Y-%m-%d.%H%M%S")
    FileUtils.cp filename, "#{filename}.#{datetime}"

    xml_file = File.new(filename, "w")
    xml_file.write(doc.to_xml(:indent => 2))
    xml_file.close
end
