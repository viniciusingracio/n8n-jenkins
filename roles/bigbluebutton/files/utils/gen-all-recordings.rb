#!/usr/bin/ruby

# depends on apt package moreutils
# run with:
# ruby gen-all-recordings.rb | ifne sponge /var/bigbluebutton/all_recordings.xml

require 'rubygems'
require 'nokogiri'

pid_file = "/var/bigbluebutton/all_recordings.pid"
begin
    pid = File.read(pid_file).to_i
    Process.getpgid(pid)
    # file exists and pid is running, so exit
    exit 0
rescue
    # just keep going
end
File.open(pid_file, "w") do |file|
    file.write(Process.pid)
end

last_modified_file = "/var/bigbluebutton/all_recordings.out"
last_modified = `find /var/bigbluebutton/published/ /var/bigbluebutton/unpublished/ /var/bigbluebutton/deleted/ -printf '%T@ %p\n' | sort -n | tail -1`.split("\n").first
if File.exists? last_modified_file
    last_modified_recorded = File.read(last_modified_file)
    exit 0 if last_modified_recorded == last_modified
end

recordings = {}
files = `find /var/bigbluebutton/published/ /var/bigbluebutton/unpublished/ -name metadata.xml`.split("\n")
files.each do |filename|
    metadata = Nokogiri::XML(File.open(filename)) { |x| x.noblanks }
    playback_node = metadata.at("/recording/playback")
    playback = playback_node.remove if ! playback_node.nil?
    download_node = metadata.at("/recording/download")
    download = download_node.remove if ! download_node.nil?

    record_id = metadata.at('/recording/id').text
    if ! recordings.has_key?(record_id)
        metadata.at("/recording/id").name = "recordID"
        metadata.at("/recording") << "<meetingID>#{metadata.at('/recording/meta/meetingId').text}</meetingID>"
        metadata.at("/recording") << "<internalMeetingID>#{metadata.at('/recording/recordID').text}</internalMeetingID>"
        metadata.at("/recording") << "<name>#{metadata.at('/recording/meta/meetingName').text}</name>"
        metadata.at("/recording") << "<isBreakout>#{metadata.at('/recording/meeting').attr('breakout')}</isBreakout>"
        [ "metadataXml", "meetingId", "meetingName", "breakout", "meeting" ].each do |node|
            metadata.at("/recording/#{node}").remove if not metadata.at("/recording/#{node}").nil?
        end

        metadata.at("/recording/start_time").name = "startTime"
        metadata.at("/recording/end_time").name = "endTime"
        metadata.at("/recording/meta").name = "metadata"
        metadata.at("/recording/raw_size").name = "rawSize"
        metadata.at("/recording/published").content = (metadata.at("/recording/state").text == "published").to_s

        metadata.at("/recording") << "<playback/>"
        metadata.at("/recording") << "<download/>"
        metadata.at("/recording") << "<size>0</size>"

        order = [ "recordID", "meetingID", "internalMeetingID", "name", "isBreakout", "published", "state", "startTime", "endTime", "participants", "rawSize", "metadata", "size", "playback", "download" ]
        root = metadata.at("/recording")
        sorted = root.children.sort_by{ |e| order.index(e.name) || order.length }
        sorted.each{ |e| root << e }

        recordings[record_id] = metadata.at("recording")
    end

    recording_node = recordings[record_id]
    if ! playback.nil? && playback.children.length > 0
        playback.name = "format"
        playback.at("format").name = "type"
        playback.at("link").name = "url"
        playback.at("processing_time").name = "processingTime" if ! playback.at("processing_time").nil?
        playback.at("duration").content = (playback.at('duration').text.to_f / 60000).to_i if ! playback.at('duration').nil?
        playback.at("duration").name = "length" if ! playback.at('duration').nil?
        if ! playback.at("extensions").nil?
            playback.at("extensions").children.each { |child| child.parent = playback }
            playback.at("extensions").remove
        end
        playback.at("extension").remove if ! playback.at("extension").nil?
        recording_node.at("size").content = recording_node.at("size").text.to_i + playback.at("size").text.to_i
        recording_node.at("playback") << playback
    end
    if ! download.nil? && download.children.length > 0
        download.name = "format"
        download.at("format").name = "type"
        download.at("link").name = "url"
        download.at("processing_time").name = "processingTime" if ! download.at("processing_time").nil?
        recording_node.at("size").content = recording_node.at("size").text.to_i + download.at("size").text.to_i
        recording_node.at("download") << download
    end
end

doc = Nokogiri::XML("<response><returncode>SUCCESS</returncode><recordings/></response>", nil, "UTF-8")
recordings_node = doc.at("/response/recordings")
recordings.values.each do |elem|
    recordings_node.add_child(elem)
end

puts doc.to_xml(:indent => 0, :encoding => "UTF-8")

File.open(last_modified_file, "w") do |file|
    file.write(last_modified)
end
