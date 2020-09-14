# encoding: UTF-8

require 'nokogiri'
require 'fileutils'

Dir.glob("/var/bigbluebutton/recording/status/published/*-presentation.fail").each do |fail_flag|
  match = /^(\w+-\d+)-presentation.fail$/.match File.basename(fail_flag)
  next if match.nil?
  record_id = match[1]
  events_xml = "/var/bigbluebutton/recording/raw/#{record_id}/events.xml"

  data = {}
  modified = false

  doc = Nokogiri::XML(File.open(events_xml)) { |x| x.noblanks }
  doc.xpath("/recording/event[@module='WHITEBOARD' and @eventname='AddShapeEvent' and ./type/text()='rectangle']").each do |event|
    shape_id = event.at_xpath("shapeId").text
    thickness_node = event.at_xpath("thickness")
    if thickness_node.nil?
      next if ! data.has_key?(shape_id)

      modified = true
      puts "ID #{record_id}, setting thickness for #{shape_id}"
      event << "<thickness>#{data[shape_id]}</thickness>"
    else
      thickness = thickness_node.text
      data[shape_id] = thickness
    end
  end

  if modified
    FileUtils.cp events_xml, "#{events_xml}.orig" if ! File.exists? "#{events_xml}.orig"
    xml_file = File.new(events_xml, "w")
    xml_file.write(doc.to_xml(:indent => 2))
    xml_file.close

    puts "Rebuilding #{record_id}"
    FileUtils.rm_rf "/var/bigbluebutton/recording/process/presentation/#{record_id}"
    FileUtils.rm_rf "/var/bigbluebutton/recording/publish/presentation/#{record_id}"
    FileUtils.rm_f "/var/bigbluebutton/recording/status/processed/#{record_id}-presentation.done"
    FileUtils.rm_f "/var/bigbluebutton/recording/status/published/#{record_id}-presentation.fail"
  end
end

Dir.glob("/var/bigbluebutton/recording/status/processed/*-presentation.fail").each do |fail_flag|
  match = /^(\w+-\d+)-presentation.fail$/.match File.basename(fail_flag)
  next if match.nil?
  record_id = match[1]
  events_xml = "/var/bigbluebutton/recording/raw/#{record_id}/events.xml"

  data = []
  modified = false

  doc = Nokogiri::XML(File.open(events_xml)) { |x| x.noblanks }
  doc.xpath("/recording/event[@module='PRESENTATION' and ( @eventname='SharePresentationEvent' or @eventname='ConversionCompletedEvent' )]").each do |event|
    event_name = event.at_xpath("@eventname").text
    presentation_name_node = event.at_xpath("presentationName")
    presentation_name = presentation_name_node.text
    case event_name
    when "ConversionCompletedEvent"
      original_filename = event.at_xpath("originalFilename").text
      data << {
        :original_filename => original_filename,
        :presentation_name => presentation_name
      }
    when "SharePresentationEvent"
      match = /^\w+-\d+$/.match presentation_name
      next if ! match.nil?

      puts
      puts "ID #{record_id}, current presentation_name: #{presentation_name}"
      candidate = data.select{ |item| presentation_name.start_with? item[:original_filename] }.first
      if candidate.nil?
        puts "  Cannot find a suitable candidate"
      else
        puts "  Candidate original filename: #{candidate[:original_filename]}"
        puts "  New presentation name: #{candidate[:presentation_name]}"
        modified = true
        presentation_name_node.content = candidate[:presentation_name]
      end
    end
  end

  if modified
    FileUtils.cp events_xml, "#{events_xml}.orig" if ! File.exists? "#{events_xml}.orig"
    xml_file = File.new(events_xml, "w")
    xml_file.write(doc.to_xml(:indent => 2))
    xml_file.close

    puts "Rebuilding #{record_id}"
    FileUtils.rm_rf "/var/bigbluebutton/recording/process/presentation/#{record_id}"
    FileUtils.rm_rf "/var/bigbluebutton/recording/publish/presentation/#{record_id}"
    FileUtils.rm_f "/var/bigbluebutton/recording/status/processed/#{record_id}-presentation.fail"
  end
end
