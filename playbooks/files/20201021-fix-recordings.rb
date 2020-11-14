# encoding: UTF-8

require 'nokogiri'
require 'fileutils'
require 'optimist'

opts = Optimist::options do
  opt :record_id, "recordID to process", :type => :string, :required => true
end

record_id = opts[:record_id]
events_xml = "/var/bigbluebutton/recording/raw/#{record_id}/events.xml"
if ! File.exists? events_xml
  puts "Cannot fix #{record_id} because raw isn't available any more"
  exit 1
end

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
