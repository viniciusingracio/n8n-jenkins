#!/usr/bin/ruby
# encoding: UTF-8

require 'trollop'
require 'date'
require 'fileutils'
require 'nokogiri'
require 'logger'

# example:
# ruby update-for-projudi.rb --xpath "/recording/meta/bbb-context" --value "2º Juizado Especial Cível"
# ruby update-for-projudi.rb --xpath "//meta/meetingId" --value "fc862dd423e83d64da82fbbf448caaa6c3e55097" --meeting-id "0018323-51.2016.8.23.0010" --dry-run
# cat /var/log/bigbluebutton/update-for-projudi.log | grep -Ev "[[:digit:]]{7}-[[:digit:]]{2}\.[[:digit:]]{4}\.[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]{3,4}"

opts = Trollop::options do
  opt :xpath, "xpath to select recordings", :type => String, :required => true
  opt :value, "value for the xpath to match", :type => String, :required => true
  opt :meeting_id, "new meetingId for the recordings", :type => String
  opt :dry_run, "do not execute anything, just search", :type => :flag, :default => false
end

logger = if opts[:dry_run]
        Logger.new(STDOUT)
    else
        Logger.new("/var/log/bigbluebutton/update-for-projudi.log")
    end
logger.level = Logger::INFO

logger.info "Migrating query \"#{opts[:xpath]}\" value \"#{opts[:value]}\""

files = `find /var/bigbluebutton/published/ /var/bigbluebutton/unpublished/ -name metadata.xml`.split("\n")
files.each do |filename|
    doc = Nokogiri::XML(File.open(filename)) { |x| x.noblanks }
    xml_node = doc.at_xpath(opts[:xpath])

    if ! xml_node.nil? && xml_node.content == opts[:value]
        xml_node = doc.at_xpath("/recording/id")
        record_id = xml_node.content

        process_number = nil
        if opts[:meeting_id].nil?
            xml_node = doc.at_xpath("/recording/meta/meetingName")
            if xml_node.nil?
                logger.error "Couldn't find /recording/meta/meetingName for #{record_id}, abort"
                next
            end
            process_number = xml_node.content
        else
            process_number = opts[:meeting_id]
        end

        xml_node = doc.at_xpath("/recording/meta/mconflb-institution-name")
        if xml_node.nil?
            logger.warn "Couldn't find /recording/meta/mconflb-institution-name for #{record_id}"
        else
            next if xml_node.content == "Projudi"
            xml_node.content = "Projudi"
        end
        logger.info "#{process_number} => #{filename}"

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

        if ! opts[:dry_run]
            datetime = DateTime.parse(File.mtime(filename).to_s).strftime("%Y-%m-%d.%H%M%S")
            FileUtils.cp filename, "#{filename}.#{datetime}"

            xml_file = File.new(filename, "w")
            xml_file.write(doc.to_xml(:indent => 2))
            xml_file.close
        end
    end
end
