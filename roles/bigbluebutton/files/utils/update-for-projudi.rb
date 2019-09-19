#!/usr/bin/ruby
# encoding: UTF-8

require 'trollop'
require 'date'
require 'fileutils'
require 'nokogiri'
require 'logger'

# example:
# ruby update-for-projudi.rb -x "/recording/meta/bbb-context" -v "2º Juizado Especial Cível"

opts = Trollop::options do
  opt :xpath, "xpath to select recordings", :type => String, :required => true
  opt :value, "value for the xpath to match", :type => String, :required => true
end

logger = Logger.new("/var/log/bigbluebutton/update-for-projudi.log")
logger.level = Logger::INFO

logger.info "Migrating \"#{opts[:value]}\""

files = `find /var/bigbluebutton/published/ /var/bigbluebutton/unpublished/ -name metadata.xml`.split("\n")
files.each do |filename|
    doc = Nokogiri::XML(File.open(filename)) { |x| x.noblanks }
    xml_node = doc.at_xpath(opts[:xpath])

    if ! xml_node.nil? && xml_node.content == opts[:value]
        xml_node = doc.at_xpath("/recording/id")
        record_id = xml_node.content

        xml_node = doc.at_xpath("/recording/meta/meetingName")
        if xml_node.nil?
            logger.error "Couldn't find /recording/meta/meetingName for #{record_id}, abort"
            next
        end
        process_number = xml_node.content
        logger.info "#{process_number} => #{filename}"

        xml_node = doc.at_xpath("/recording/meta/mconflb-institution-name")
        if xml_node.nil?
            logger.warn "Couldn't find /recording/meta/mconflb-institution-name for #{record_id}"
        else
            xml_node.content = "Projudi"
        end

        xml_node = doc.at_xpath("/recording/meta/mconflb-institution")
        if xml_node.nil?
            logger.warn "Couldn't find /recording/meta/mconflb-institution for #{record_id}"
        else
            xml_node.content = "4"
        end

        xml_node = doc.at_xpath("/recording/meta/meetingId")
        if xml_node.nil?
            logger.warn "Couldn't find /recording/meta/meetingId for #{record_id}"
        else
            xml_node.content = process_number
        end

        xml_node = doc.at_xpath("/recording/meeting/@externalId")
        if xml_node.nil?
            logger.warn "Couldn't find /recording/meeting/@externalId for #{record_id}"
        else
            xml_node.content = process_number
        end

        datetime = DateTime.parse(File.mtime(filename).to_s).strftime("%Y-%m-%d.%H%M%S")
        FileUtils.cp filename, "#{filename}.#{datetime}"

        xml_file = File.new(filename, "w")
        xml_file.write(doc.to_xml(:indent => 2))
        xml_file.close
    end
end
