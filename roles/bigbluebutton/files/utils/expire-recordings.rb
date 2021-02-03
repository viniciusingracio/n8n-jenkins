#!/usr/bin/ruby
# encoding: UTF-8

# sudo gem install optimist tz

# Example:
# ruby expire-recordings.rb --xpath "/recording/meta/mconf-secret-name" --value "Moodle-UFBA-1" --age 180 --dry-run
# ruby expire-recordings.rb --xpath "/recording/meta/mconf-subnet" --value "Global" --age 90 --dry-run | grep -v 'Delete URL' | wc -l

require 'optimist'
require 'nokogiri'
require 'date'
require 'fileutils'
require 'tz'
require 'logger'
require 'net/http'
require 'digest/sha1'

opts = Optimist::options do
  opt :xpath, "xpath to select recordings", :type => :string, :required => true
  opt :value, "regex for the xpath to match", :type => :string, :required => true
  opt :age, "Remove recordings older than age (in days)", :type => :int, :required => true
  opt :dry_run, "Do not execute anything, just search", :type => :flag, :default => false
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

expired = []

files = `find /var/bigbluebutton/published/presentation/ /var/bigbluebutton/unpublished/presentation/ -name metadata.xml`.split("\n")
files.each do |filename|
    doc = Nokogiri::XML(File.open(filename), nil, "UTF-8") { |x| x.noblanks }

    xml_node = doc.at_xpath(opts[:xpath])
    next if xml_node.nil? || xml_node.content != opts[:value]

    xml_node = doc.at_xpath("/recording/id")
    record_id = xml_node.content

    date = timestamp_to_date(record_id_to_timestamp(record_id))
    next unless (DateTime.now - date).to_i > opts[:age]

    xml_node = doc.at_xpath("/recording/meta/mconf-institution-name")
    institution_name = xml_node.content
    xml_node = doc.at_xpath("/recording/meta/mconf-secret-name")
    secret_name = xml_node.content
    xml_node = doc.at_xpath("/recording/state")
    state = xml_node.content

    expired << {
        :date => date,
        :record_id => record_id,
        :state => state,
        :institution_name => institution_name,
        :secret_name => secret_name
    }
end
expired.sort_by! { |r| r[:date] }

logger = if opts[:dry_run]
        Logger.new(STDOUT)
    else
        Logger.new("/var/log/bigbluebutton/expire-recordings.log")
    end
logger.level = Logger::INFO

properties = Hash[File.read("/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties", :encoding => "ISO-8859-1:UTF-8").scan(/(.+?)=(.+)/)]
server_url = properties['bigbluebutton.web.serverURL']
server_secret = properties['securitySalt']

expired.each do |obj|
  logger.info "Recording made in #{format_date_time(obj[:date])}, ID #{obj[:record_id]}, state #{obj[:state]}, institution #{obj[:institution_name]}, secret #{obj[:secret_name]}"
  uri = auth_uri(server_url, server_secret, "deleteRecordings", "recordID=#{obj[:record_id]}")
  unless opts[:dry_run]
    begin
      req = Net::HTTP::Get.new(uri.to_s)
      res = Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') { |http| http.request(req) }
      unless res.kind_of? Net::HTTPSuccess
        logger.warn "#{res.body}"
      end
    rescue Exception => e
      logger.error "Failed to request #{uri.to_s}"
    end
  end
end
