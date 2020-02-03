#!/usr/bin/ruby
# encoding: UTF-8

require 'trollop'
require 'date'
require 'fileutils'
require 'nokogiri'
require 'logger'
require 'set'

opts = Trollop::options do
  opt :list, "file to list of process", :type => String, :required => true
  opt :dry_run, "do not execute anything, just search", :type => :flag, :default => false
end

logger = if opts[:dry_run]
        Logger.new(STDOUT)
    else
        Logger.new("check-process-number.log")
    end
logger.level = Logger::INFO

set = Set.new
File.open(opts[:list],'r').each { |line| set << line.strip }
pattern_cnj = /^\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.\d{4}$/

files = `find /var/bigbluebutton/published/ /var/bigbluebutton/unpublished/ -name metadata.xml`.split("\n")
files.each do |filename|
    doc = Nokogiri::XML(File.open(filename)) { |x| x.noblanks }

    xml_node = doc.at_xpath("/recording/meta/mconflb-institution-name")
    next if xml_node.nil? or xml_node.content != "Projudi"

    xml_node = doc.at_xpath("/recording/id")
    record_id = xml_node.content

    xml_node = doc.at_xpath("/recording/meta/meetingName")
    if xml_node.nil?
        logger.error "Couldn't find /recording/meta/meetingName for #{record_id}, abort"
        next
    end
    process_number = xml_node.content
    next if pattern_cnj.match(process_number).nil?

    logger.info "#{process_number} (ID #{record_id}) has't been found" if ! set.include?(process_number.gsub(/-|\./, ""))
end
