#!/usr/bin/ruby
# encoding: UTF-8

# sudo gem install optimist tz

# Example:
# ruby expire-recordings.rb --xpath "/recording/meta/mconf-secret-name[text()='Moodle-UFBA-1']" --age 180 --dry-run
# ruby expire-recordings.rb --xpath "/recording/meta/mconf-subnet[text()='Global']" --age 90 --dry-run
# ruby expire-recordings.rb --xpath "/recording/meta/bbb-origin[text()='Moodle']" --age 15 --dry-run
# ruby expire-recordings.rb --xpath "/recording/id[text()='6ee17cc67b228fa5bca5e399483f66c7dda851f1-1545311689704']" --age 90 --dry-run
# ruby expire-recordings.rb --xpath "." --age 120 --dry-run

require 'date'
require 'digest/sha1'
require 'fileutils'
require 'logger'
require 'net/http'
require 'nokogiri'
require 'optimist'
require 'tz'

require '/usr/local/bigbluebutton/core/lib/recordandplayback.rb'

opts = Optimist::options do
  opt :conf, "Path to the config file", :type => :string
  opt :xpath, "xpath to select recordings", :type => :string
  opt :age, "Remove recordings older than age (in days)", :type => :int
  opt :dry_run, "Do not execute anything, just search", :type => :flag, :default => false
  opt :method, "Choose if delete will occur with api or file", :type => :string, :default => "file"
end

def timestamp_to_date(ms)
    DateTime.strptime(ms.to_s,'%Q')
end

def format_date_time(d, timezone_s = "America/Sao_Paulo")
    timezone = TZInfo::Timezone.get(timezone_s)
    local_date = timezone.utc_to_local(d)
    local_date.strftime("%Y-%m-%d %H:%M:%S")
end

def record_id_to_timestamp(r)
    r.split("-")[1].to_i
end

def auth_uri(server_url, server_secret, method, params=nil)
  params ||= "random=#{rand(99999)}"
  checksum = Digest::SHA1.hexdigest "#{method}#{params}#{server_secret}"
  URI::join(server_url, "bigbluebutton/api/#{method}?#{params}&checksum=#{checksum}")
end

logger = if opts[:dry_run]
        Logger.new(STDOUT)
    else
        Logger.new("/var/log/bigbluebutton/expire-recordings.log")
    end
logger.level = Logger::INFO

unless ! opts[:conf].nil? ^ ( ! opts[:xpath].nil? and ! opts[:age].nil? )
  logger.error "You must specify conf OR xpath and age"
  exit 1
end

unless [ "api", "file" ].include? opts[:method]
  logger.error "Invalid method: #{opts[:method]}"
  exit 1
end

conditions = []
if ! opts[:conf].nil?
  props = YAML::load(File.read(opts[:conf]))
  conditions = props["conditions"]

  if conditions.empty?
    logger.warn "Config file has no condition defined"
    exit 0
  end
else
  conditions = [ { "xpath" => opts[:xpath], "age" => opts[:age] } ]
end

expired = []

`find /var/bigbluebutton/published/presentation/ /var/bigbluebutton/unpublished/presentation/ -name metadata.xml`.split("\n").each do |filename|
    doc = Nokogiri::XML(File.read(filename), nil, "UTF-8") { |x| x.noblanks }

    xml_node = doc.at_xpath("/recording/id")
    record_id = xml_node.content

    recorded_at = timestamp_to_date(record_id_to_timestamp(record_id))

    next unless conditions.any? { |condition| ! doc.at_xpath(condition["xpath"]).nil? and (DateTime.now - recorded_at).to_i > condition["age"] }

    xml_node = doc.at_xpath("/recording/meta/mconf-institution-name")
    xml_node = doc.at_xpath("/recording/meta/mconflb-institution-name") if xml_node.nil?
    institution_name = xml_node.nil? ? "<unset>" : xml_node.content

    xml_node = doc.at_xpath("/recording/meta/mconf-secret-name")
    secret_name = xml_node.nil? ? "<unset>" : xml_node.content

    xml_node = doc.at_xpath("/recording/state")
    state = xml_node.content

    expired << {
        :date => recorded_at,
        :record_id => record_id,
        :state => state,
        :institution_name => institution_name,
        :secret_name => secret_name
    }
end
expired.sort_by! { |r| r[:date] }

server_url, server_secret = [ nil, nil ]
if opts[:method] == "api"
  properties = Hash[File.read("/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties", :encoding => "ISO-8859-1:UTF-8").scan(/(.+?)=(.+)/)]
  server_url = properties['bigbluebutton.web.serverURL']
  server_secret = properties['securitySalt']
end

if opts[:method] == "file"
  props = YAML::load(File.read('/usr/local/bigbluebutton/core/scripts/bigbluebutton.yml'))
  redis_host = props['redis_host']
  redis_port = props['redis_port']
  redis_password = props['redis_password']
  BigBlueButton.redis_publisher = BigBlueButton::RedisWrapper.new(redis_host, redis_port, redis_password)
end

summary = {
  :count => 0,
  :bytes => 0
}

unless expired.empty?
  logger.info "Expire recordings using the following conditions: #{conditions.to_s}"
end

expired.each do |obj|
  logger.info "Recording made in #{format_date_time(obj[:date])}, ID #{obj[:record_id]}, state #{obj[:state]}, institution #{obj[:institution_name]}, secret #{obj[:secret_name]}"

  Dir.glob(["/var/bigbluebutton/published/*/#{obj[:record_id]}/metadata.xml", "/var/bigbluebutton/unpublished/*/#{obj[:record_id]}/metadata.xml"]).each do |filename|
    doc = Nokogiri::XML(File.read(filename), nil, "UTF-8") { |x| x.noblanks }

    xml_node = doc.at_xpath("/recording/playback/size")
    summary[:bytes] += xml_node.content.to_i unless xml_node.nil?
  end

  summary[:count] += 1

  next if opts[:dry_run]

  case opts[:method]
  when "api"
    uri = auth_uri(server_url, server_secret, "deleteRecordings", "recordID=#{obj[:record_id]}")
    begin
      req = Net::HTTP::Get.new(uri.to_s)
      res = Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') { |http| http.request(req) }
      unless res.kind_of? Net::HTTPSuccess
        logger.warn "#{res.body}"
      end
    rescue Exception => e
      logger.error "Failed to request #{uri.to_s}"
    end
  when "file"
    Dir.glob(["/var/bigbluebutton/published/*/#{obj[:record_id]}/metadata.xml", "/var/bigbluebutton/unpublished/*/#{obj[:record_id]}/metadata.xml"]).each do |filename|
      datetime = DateTime.parse(File.mtime(filename).to_s).strftime("%Y-%m-%d.%H%M%S")
      FileUtils.cp filename, "#{filename}.#{datetime}"

      doc = Nokogiri::XML(File.read(filename), nil, "UTF-8") { |x| x.noblanks }
      xml_node = doc.at_xpath("/recording/state")
      xml_node.content = "deleted"

      xml_node = doc.at_xpath("/recording/published")
      xml_node.content = "false"

      xml_file = File.new(filename, "w")
      xml_file.write(doc.to_xml(:indent => 2))
      xml_file.close

      xml_node = doc.at_xpath("/recording/playback/format")
      format = xml_node.content

      dir = File.dirname(filename)
      FileUtils.mv dir, "/var/bigbluebutton/deleted/#{format}/#{obj[:record_id]}"
      logger.debug "D format #{format} to deleted"
    end

    # publish the news to redis
    BigBlueButton.redis_publisher.put_message("deleted", obj[:record_id])
    # give some time to trigger the redis message
    sleep 0.1
  end
end

unless expired.empty?
  logger.info "Summary: deleted #{summary[:count]} recordings (#{(summary[:bytes] / (2**30).to_f).round(1)} GB)"
end
