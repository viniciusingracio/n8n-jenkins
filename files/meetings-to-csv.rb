# encoding: UTF-8

# sudo gem install user_agent_parser -v 2.5.1

require 'nokogiri'
require 'date'
require 'json'
require 'optimist'
require 'csv'
require 'histogram/array'
require 'logger'
require 'pp'
require 'user_agent_parser'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

opts = Optimist::options do
  opt :server, "server", :type => String, :required => true
end

def record_id_to_timestamp(r)
    r.split("-")[1].to_i
end

def timestamp_to_date(ms)
  DateTime.strptime(ms.to_s,'%Q')
end

def format_date_time(d)
  # timezone = TZInfo::Timezone.get("America/Sao_Paulo")
  # local_date = timezone.utc_to_local(d)
  # local_date.strftime("%d/%m/%Y %H:%M:%S")
  d.strftime("%d/%m/%Y %H:%M:%S")
end

def format_date_from_record_id(r)
  format_date_time(timestamp_to_date(record_id_to_timestamp(r)))
end

def save_to_cache(data, filename)
  File.open(filename, "w") do |file|
    Marshal.dump(data, file)
  end
end

def read_from_cache(filename)
  File.open(filename, "r") do |file|
    Marshal.load(file)
  end
end

audio_histogram_bucket = [ 0, 25, 50, 60, 70, 80, 85, 90, 95, 100 ]
logger = Logger.new(STDOUT)

data_by_session = {}
data_by_user = {}

if File.exists? "/tmp/cache-events-session.dat"
    logger.info "Read events.xml data from cache"

    data_by_session = read_from_cache("/tmp/cache-events-session.dat")
    data_by_session.values.each do |item|
        item[:users].each do |user|
            data_by_user[user[:user_id]] = user
        end
    end
end

logger.info "Start parsing events.xml"

Dir.glob("/var/bigbluebutton/events/**/events.xml").each do |events_xml|
    session_id = File.basename(File.dirname(events_xml))
    next if data_by_session.has_key?(session_id)
    begin
        doc = Nokogiri::XML(File.open(events_xml)) { |x| x.noblanks }

        next if doc.xpath("/recording/event").length == 0
        item = {}
        item[:server] = opts[:server]
        item[:session_id] = doc.at_xpath("/recording/@meeting_id").text
        first_event_timestamp = timestamp_to_date(doc.at_xpath('/recording/event[position() = 1]/timestampUTC').text)
        last_event_timestamp = timestamp_to_date(doc.at_xpath('/recording/event[position() = last()]/timestampUTC').text)
        item[:date] = first_event_timestamp
        item[:meeting_id] = doc.at_xpath("/recording/meeting/@externalId").text
        item[:meeting_name] = doc.at_xpath("/recording/meeting/@name").text
        item[:client] = nil
        node = doc.at_xpath("/recording/metadata/@mconflb-institution-name")
        if node
            item[:client] = node.text
        else
            node = doc.at_xpath("/recording/metadata/@mconf-institution-name")
            if node
                item[:client] = node.text
            end
        end
        item[:recorded_minutes] = 0
        start = nil
        doc.xpath("/recording/event[@module='PARTICIPANT' and @eventname='RecordStatusEvent']").each do |node|
            status = node.at_xpath("status").text
            timestamp_utc = timestamp_to_date(node.at_xpath("timestampUTC").text)
            if status == "true"
                start = timestamp_utc
            else
                item[:recorded_minutes] += ((timestamp_utc - start) * 24 * 60).to_i
                start = nil
            end
        end
        item[:recorded_minutes] += ((last_event_timestamp - start) * 24 * 60).to_i if ! start.nil?
        item[:duration_minutes] = ((last_event_timestamp - first_event_timestamp) * 24 * 60).to_i
        item[:has_presentation] = doc.xpath("/recording/event[@module='PRESENTATION' and @eventname='ConversionCompletedEvent']").length > 1
        item[:has_annotation] = doc.xpath("/recording/event[@module='WHITEBOARD' and @eventname='AddShapeEvent']").length > 1
        item[:has_screenshare] = doc.xpath("/recording/event[@module='bbb-webrtc-sfu' and @eventname='StartWebRTCDesktopShareEvent']").length > 1
        item[:has_poll] = doc.xpath("/recording/event[@module='POLL' and @eventname='PollStartedRecordEvent']").length > 1

        item[:users] = []
        doc.xpath("/recording/event[@module='PARTICIPANT' and @eventname='ParticipantJoinEvent']").each do |node|
            user_id = node.at_xpath("userId").text
            user = data_by_user[user_id]
            if user
                user[:reconnect] += 1
                next
            end

            timestamp_utc = timestamp_to_date(node.at_xpath("timestampUTC").text)
            user = {}
            user[:user_id] = user_id
            user[:external_user_id] = node.at_xpath("externalUserId").text
            user[:name] = node.at_xpath("name").text
            user[:role] = node.at_xpath("role").text
            user[:join] = timestamp_utc
            leave_node = doc.xpath("/recording/event[@module='PARTICIPANT' and @eventname='ParticipantLeftEvent' and userId='#{user_id}'][position() = last()]/timestampUTC")
            if leave_node.empty?
                user[:leave] = last_event_timestamp
            else
                user[:leave] = timestamp_to_date(leave_node.text)
            end

            user[:audio_enabled] = nil
            user[:audio_disabled] = nil
            audio_node = doc.xpath("/recording/event[@module='VOICE' and @eventname='ParticipantJoinedEvent' and participant='#{user_id}'][position() = 1]/timestampUTC")
            if ! audio_node.empty?
                user[:audio_enabled] = timestamp_to_date(audio_node.text)
            end
            audio_node = doc.xpath("/recording/event[@module='VOICE' and @eventname='ParticipantLeftEvent' and participant='#{user_id}'][position() = last()]/timestampUTC")
            if ! audio_node.empty?
                user[:audio_disabled] = timestamp_to_date(audio_node.text)
            else
                user[:audio_disabled] = last_event_timestamp if ! user[:audio_enabled].nil?
            end
            user[:joined_echo] = false
            user[:joined_conference] = false
            user[:joined_listen_only] = false

            user[:has_chat] = doc.xpath("/recording/event[@module='CHAT' and @eventname='PublicChatEvent' and senderId='#{user_id}']").length > 1
            user[:has_video] = false
            user[:audio_quality_average] = nil
            audio_histogram_bucket.each_with_index do |size, index|
                user["audio_quality_bucket_#{size}".to_sym] = nil
            end
            user[:talked] = doc.xpath("/recording/event[@module='VOICE' and @eventname='ParticipantTalkingEvent' and participant='#{user_id}']").length > 1
            user[:reconnect] = 0
            user[:ip] = nil
            user[:log_info] = 0
            user[:log_warn] = 0
            user[:log_error] = 0
            user[:agent_family] = nil
            user[:agent_version] = nil
            user[:agent_os] = nil
            user[:agent_device] = nil
            user[:audio_failure] = 0
            user[:audio_joined] = 0
            user[:build] = nil
            item[:users] << user
            data_by_user[user_id] = user
        end

        doc.xpath("/recording/event[@module='bbb-webrtc-sfu' and @eventname='StartWebRTCShareEvent']").each do |node|
            filename = node.at_xpath("filename").text
            match = /.*\w+-\d+\/\w+-(?<user_id>\w_\w+)-\d+.\w+/.match filename
            next if match.nil?
            user_id = match[:user_id]
            user = data_by_user[user_id]
            if user
                user[:has_video] = true
            end
        end

        data_by_session[item[:session_id]] = item
    rescue Exception => e
        logger.error "Failed to process #{events_xml}"
        puts e.message
        e.backtrace.each do |traceline|
            puts traceline
        end
        exit 1
    end
end

save_to_cache(data_by_session, "/tmp/cache-events-session.dat")

logger.info "Start parsing client logs"

log_codes = {}

`ls -tr1 /var/log/nginx/html5-client.log*`.split("\n").each do |log_file|
    logger.info "Parsing #{log_file}"
    if File.extname(log_file) == ".gz"
        lines = `zcat #{log_file}`.split("\n")
    else
        lines = File.readlines(log_file)
    end
    lines.each do |line|
        parsed = JSON.parse(line, symbolize_names: true)
        next if ! parsed[:nginx][:request_body] || parsed[:nginx][:request_body].empty?
        parsed[:nginx][:request_body] = JSON.parse(parsed[:nginx][:request_body], symbolize_names: true)

        ip = parsed[:nginx][:access][:remote_ip]
        agent = UserAgentParser.parse parsed[:nginx][:access][:agent]

        parsed[:nginx][:request_body].each do |body|
            next if ! body[:userInfo] || body[:userInfo].empty?
            session_id = body[:userInfo][:meetingId]
            next if ! data_by_session.has_key?(session_id)

            # timestamp = body[:time] #2019-12-03T16:56:08.104Z
            user_id = body[:userInfo][:requesterUserId]
            build = body[:clientBuild]
            log_code = body[:logCode]
            log_level = body[:level]
            log_name = body[:levelName]

            user = data_by_user[user_id]
            if user
                user[:ip] = ip
                user[:agent_family] = agent.family
                user[:agent_version] = agent.version.to_s
                user[:agent_os] = agent.os.to_s
                user[:agent_device] = agent.device.family
                user[:build] = build

                case log_level
                when 30
                    user[:log_info] += 1
                when 40
                    user[:log_warn] += 1
                when 50
                    user[:log_error] += 1
                end

                case log_code
                when "audio_failure"
                    user[:audio_failure] += 1
                when "audio_joined"
                    user[:audio_joined] += 1
                end
            end

            if log_codes[log_code]
                log_codes[log_code] += 1
            else
                log_codes[log_code] = 1
            end
        end
    end
end

puts JSON.pretty_generate(Hash[log_codes.sort_by{ |key, value| -value }] )

logger.info "Start parsing audio stats"

missing = 0

audio_stats = {}
`ls -tr1 /var/log/bigbluebutton/audio-stats.log*`.split("\n").each do |filename|
    logger.info "Parsing #{filename}"
    lines = File.readlines(filename)
    lines.each do |line|
        match = /(?<log_level_code>\w+), \[(?<date>[^ ]*) #(?<pid>\d+)\]\s+(?<log_level>\w+) -- : (?<json>.*)/.match line
        next if match.nil?

        parsed = JSON.parse(match[:json], symbolize_names: true)
        timestamp = DateTime.strptime(match[:date], '%Y-%m-%dT%H:%M:%S.%L')
        session_id = parsed[:meeting][:internalMeetingID]
        if ! data_by_session.has_key?(session_id)
            missing += 1
            next
        end

        if parsed[:audio].empty?
            user_id = parsed[:user_id]
            user = data_by_user[user_id]
            if user
            else
                user_candidates = data_by_session[session_id][:users].select{ |user| user[:external_user_id] == parsed[:userID] and ! user[:audio_enabled].nil? and user[:audio_enabled] <= timestamp and user[:audio_disabled] >= timestamp }
                user_candidates.each do |user|
                    user[:joined_listen_only] |= parsed[:isListeningOnly]
                end
            end
            next
        end

        uuid = parsed[:audio][:uuid]
        user_id = parsed[:audio][:user_id]
        stats = audio_stats[uuid]
        if stats.nil?
            stats = {
                :uuid => uuid,
                :user_id => user_id,
                :session_id => session_id,
                :timestamp => DateTime.strptime(parsed[:audio][:timestamp]),
                :join_echo => false,
                :join_conference => false,
                :quality => []
            }
            audio_stats[uuid] = stats
        end
        stats[:listen_only] |= parsed[:isListeningOnly]
        stats[:join_echo] |= parsed[:audio][:is_echo]
        stats[:join_conference] |= parsed[:audio][:is_conference]
        stats[:quality] << parsed[:audio][:stats][:audio][:in_quality_percentage] if ! parsed[:audio][:stats][:audio].empty?
    end
end

logger.info "Could not match a total of #{missing} samples of audio stats with a valid session_id"

missing = 0

audio_stats.values.each do |stats|
    user = nil
    begin
        user = data_by_user[stats[:user_id]]
        if user
            data_sum = 0
            stats[:quality].each { |x| data_sum += x }
            (bins, freqs) = stats[:quality].histogram(audio_histogram_bucket, :bin_boundary => :min)
            sum = 0
            freqs.map! { |x| sum += x }

            audio_histogram_bucket.each_with_index do |size, index|
                user["audio_quality_bucket_#{size}".to_sym] = freqs[index].to_i
            end
            user[:audio_quality_average] = (data_sum.to_f / stats[:quality].length).round(2)
            user[:joined_echo] = stats[:join_echo]
            user[:joined_conference] = stats[:join_conference]
        else
            missing += 1
        end
    rescue Exception => e
        logger.trace PP.pp(stats)
        logger.trace PP.pp(user)
        logger.error e.message
        e.backtrace.each do |traceline|
            logger.error traceline
        end

        exit 1
    end
end

logger.info "Could not match a total of #{missing} samples of audio stats"

logger.info "Writing to file"

# s = CSV.generate do |csv|
CSV.open("/tmp/stats.csv", "w", {:col_sep => "\t"}) do |csv|
    csv.to_io.write "\uFEFF"
    csv << data_by_session.values.first.keys + data_by_session.values.first[:users].first.keys - [ :users ]
    data_by_session.values.sort_by{ |item| item[:date] }.each do |item|
        item[:date] = format_date_time(item[:date])
        users = item.delete(:users)
        users.sort_by{ |user| user[:join] }.each do |user|
            user[:join] = format_date_time(user[:join])
            user[:leave] = format_date_time(user[:leave])
            user[:audio_enabled] = format_date_time(user[:audio_enabled]) if ! user[:audio_enabled].nil?
            user[:audio_disabled] = format_date_time(user[:audio_disabled]) if ! user[:audio_disabled].nil?
            csv << item.values + user.values
        end
    end
end
# puts s
