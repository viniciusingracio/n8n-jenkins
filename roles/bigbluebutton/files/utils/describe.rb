# encoding: UTF-8

# sudo gem install optimist tz terminal-table

require 'nokogiri'
require 'date'
require 'json'
require 'optimist'
require 'csv'
require 'logger'
require 'pp'
require 'tz'
require 'terminal-table'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

def timestamp_to_date(ms)
    DateTime.strptime(ms.to_s,'%Q')
end

def format_date_time(d, timezone_s = nil)
    timezone_s ||= $timezone
    timezone = TZInfo::Timezone.get(timezone_s)
    local_date = timezone.utc_to_local(d)
    local_date.strftime("%d/%m/%Y %H:%M:%S")
end

def seconds_to_duration(t)
    Time.at(t).utc.strftime("%H:%M:%S")
end

opts = Optimist::options do
    opt :events_xml, "Path to events.xml", :type => String, :required => true
    opt :timezone, "Timezone", :type => String, :required => false, :default => "America/Sao_Paulo"
end

events_xml = opts[:events_xml]
$timezone = opts[:timezone]

doc = Nokogiri::XML(File.open(events_xml)) { |x| x.noblanks }

user_id_to_name = {}
events = []

record_duration_sec = 0
record_last_segment = 0
start_recording = nil

talking = {}

doc.xpath("/recording/event").sort_by{ |node| node.at_xpath("@timestamp").text.to_i }.each do |node|
    event_module = node.at_xpath("@module").text
    event_name = node.at_xpath("@eventname").text
    timestamp = node.at_xpath("@timestamp").text.to_i
    timestamp_utc = node.at_xpath("timestampUTC").text.to_i
    date_utc = timestamp_to_date(timestamp_utc)
    record_duration_sec = events.empty? ? 0 : events.last[:record_duration_sec]
    if ! start_recording.nil?
        record_duration_sec = record_last_segment + ((date_utc - start_recording) * 24 * 60 * 60).to_i
    end
    event = {
        :timestamp => timestamp,
        :timestamp_utc => timestamp_utc,
        :date => date_utc,
        :record_duration_sec => record_duration_sec,
        :record_duration => seconds_to_duration(record_duration_sec)
    }
    if event_module == "PARTICIPANT"
        case event_name
        when "ParticipantJoinEvent"
            user_id = node.at_xpath("userId").text
            user_name = node.at_xpath("name").text
            user_id_to_name[user_id] = user_name
            event.merge!({
                :user => user_name,
                :event => "Joined the session"
            })
            events << event
        when "ParticipantLeftEvent"
            user_id = node.at_xpath("userId").text
            user_name = user_id_to_name[user_id]
            event.merge!({
                :user => user_name,
                :event => "Left the session"
            })
            events << event
        when "RecordStatusEvent"
            user_id = node.at_xpath("userId").text
            user_name = user_id_to_name[user_id]
            status = node.at_xpath("status").text == "true"
            if status
                start_recording = date_utc
            else
                start_recording = nil
                record_last_segment = record_duration_sec
            end
            event.merge!({
                :user => user_name,
                :event => "** Session #{status ? 'started' : 'stopped'} being recorded"
            })
            events << event
        end
    elsif event_module == "VOICE"
        case event_name
        when "ParticipantJoinedEvent"
            user_id = node.at_xpath("participant").text
            user_name = user_id_to_name[user_id]
            message = node.at_xpath("muted").text == "true" ? "Enabled to listen" : "Enabled microphone"
            event.merge!({
                :user => user_name,
                :event => message
            })
            events << event
        when "ParticipantLeftEvent"
            user_id = node.at_xpath("participant").text
            user_name = user_id_to_name[user_id]
            event.merge!({
                :user => user_name,
                :event => "Disabled audio"
            })
            events << event
        when "ParticipantTalkingEvent"
            user_id = node.at_xpath("participant").text
            user_name = user_id_to_name[user_id]
            status = node.at_xpath("talking").text == "true"
            event[:user] = user_name
            if ! talking.has_key?(user_id)
                event[:event] = "First talking event"
                talking[user_id] = []
            else
                talking[user_id].pop if talking[user_id].length == 2
                event[:event] = "Last talking event"
            end
            talking[user_id] << event
        end
    elsif event_module == "bbb-webrtc-sfu"
        filename = node.at_xpath("filename").text
        match = /.*\w+-\d+\/\w+-(?<user_id>\w_\w+)-\d+.\w+/.match filename
        if ! match.nil?
            user_id = match[:user_id]
            user_name = user_id_to_name[user_id]
            case event_name
            when "StartWebRTCShareEvent"
                event.merge!({
                    :user => user_name,
                    :event => "Enabled camera"
                })
                events << event
            when "StopWebRTCShareEvent"
                event.merge!({
                    :user => user_name,
                    :event => "Disabled camera"
                })
                events << event
            end
        end
    end
end

talking.values.each do |entry|
    entry.each do |event|
        events << event
    end
end

exit 0 if events.length == 0

events.each do |event|
    event[:date] = format_date_time(event[:date])
end
events.sort_by! { |event| event[:timestamp] }

puts Terminal::Table.new :headings => events.first.keys.map{ |entry| entry.to_s }, :rows => events.map{ |entry| entry.values }
