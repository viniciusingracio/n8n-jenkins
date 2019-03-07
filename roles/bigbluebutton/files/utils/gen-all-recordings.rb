#!/usr/bin/ruby

require 'rubygems'
require 'nokogiri'

recordings = {}
files = `find /var/bigbluebutton/published /var/bigbluebutton/unpublished -name metadata.xml`.split("\n")
files.each do |filename|
    metadata = Nokogiri::XML(File.open(filename)) { |x| x.noblanks }
    playback = metadata.at("/recording/playback").remove

    record_id = metadata.at('/recording/id').text
    if ! recordings.has_key?(record_id)
        metadata.at("/recording/id").name = "recordID"
        metadata.at("/recording") << "<meetingID>#{metadata.at('/recording/meta/meetingId').text}</meetingID>"
        metadata.at("/recording") << "<internalMeetingID>#{metadata.at('/recording/recordID').text}</internalMeetingID>"
        metadata.at("/recording") << "<name>#{metadata.at('/recording/meta/meetingName').text}</name>"
        metadata.at("/recording") << "<isBreakout>#{metadata.at('/recording/meeting').attr('breakout')}</isBreakout>"
        [ "metadataXml", "meetingId", "meetingName", "breakout", "meeting", "participants", "download" ].each do |node|
          metadata.at("/recording/#{node}").remove if not metadata.at("/recording/#{node}").nil?
        end

        metadata.at("/recording/start_time").name = "startTime"
        metadata.at("/recording/end_time").name = "endTime"
        metadata.at("/recording/meta").name = "metadata"
        metadata.at("/recording/raw_size").name = "rawSize"
        if metadata.at("/recording/published").text == "true"
            metadata.at("/recording/state").content = "published"
        else
            metadata.at("/recording/state").content = "unpublished"
        end

        metadata.at("/recording") << "<playback/>"
        metadata.at("/recording/playback") << "<format><type>#{playback.at('format').text}</type><url>#{playback.at('link').text}</url><processingTime>#{if playback.at('processing_time').nil? ? 0 : playback.at('processing_time').text}</processingTime><size>#{playback.at('size').text}</size><length>#{(playback.at('duration').text.to_f / 60000).to_i}</length></format>"

        order = [ "recordID", "meetingID", "internalMeetingID", "name", "isBreakout", "published", "state", "startTime", "endTime", "size", "rawSize", "metadata", "playback", "download" ]
        root = metadata.at("/recording")
        sorted = root.children.sort_by{ |e| order.index(e.name) || order.length }
        sorted.each{ |e| root << e }

        recordings[record_id] = metadata.at("recording")
    else
        recording_node = recordings[record_id]
        recording_node.at("playback") << "<format><type>#{playback.at('format').text}</type><url>#{playback.at('link').text}</url><processingTime>#{playback.at('processing_time').text}</processingTime><size>#{playback.at('size').text}</size><length>#{(playback.at('duration').text.to_f / 60000).to_i}</length></format>"
    end
end

doc = Nokogiri::XML("<response><returncode>SUCCESS</returncode><recordings/></response>", nil, "UTF-8")
recordings_node = doc.at("/response/recordings")
recordings.values.each do |elem|
  recordings_node.add_child(elem)
end

puts doc.to_xml(:indent => 0, :encoding => "UTF-8")
