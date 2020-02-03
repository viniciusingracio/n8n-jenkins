#!/usr/bin/ruby
# encoding: UTF-8

require 'trollop'
require 'date'
require 'fileutils'
require 'nokogiri'
require 'logger'

opts = Trollop::options do
  opt :dry_run, "do not execute anything, just search", :type => :flag, :default => false
end

logger = if opts[:dry_run]
        Logger.new(STDOUT)
    else
        Logger.new("/var/log/bigbluebutton/fix-process-number.log")
    end
logger.level = Logger::INFO

pattern_cnj = /^\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.\d{4}$/
pattern_recover = /(?:^|.*\D)[0]*(?<p1>\d{7})(?:-)?(?<p2>\d{2})(?:\.)?(?<p3>\d{4})(?:\.)?(?<p4>\d)(?:\.)?23(?:\.)?(?<p5>\d{4})(?:$|\D.*)/

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
    meeting_name = xml_node.content
    next if ! pattern_cnj.match(meeting_name).nil?

    m = pattern_recover.match(meeting_name)
    next if m.nil?

    process_number = "%s-%s.%s.%s.23.%s" % [ m[:p1], m[:p2], m[:p3], m[:p4], m[:p5] ]

    [ "/recording/meta/meetingId", "/recording/meta/meetingName", "/recording/meeting/@externalId", "/recording/meeting/@name"].each do |xpath|
        xml_node = doc.at_xpath(xpath)
        if xml_node.nil?
            logger.warn "Couldn't find #{xpath} for #{record_id}"
        else
            xml_node.content = process_number
        end
    end

    logger.info "#{meeting_name} => #{process_number} (#{filename})"

    if ! opts[:dry_run]
        datetime = DateTime.parse(File.mtime(filename).to_s).strftime("%Y-%m-%d.%H%M%S")
        FileUtils.cp filename, "#{filename}.#{datetime}"

        xml_file = File.new(filename, "w")
        xml_file.write(doc.to_xml(:indent => 2))
        xml_file.close
    end
end
