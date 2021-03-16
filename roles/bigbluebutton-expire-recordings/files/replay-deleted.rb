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

props = YAML::load(File.read('/usr/local/bigbluebutton/core/scripts/bigbluebutton.yml'))
redis_host = props['redis_host']
redis_port = props['redis_port']
redis_password = props['redis_password']
BigBlueButton.redis_publisher = BigBlueButton::RedisWrapper.new(redis_host, redis_port, redis_password)

`find /var/bigbluebutton/deleted/presentation/ -name metadata.xml`.split("\n").each do |filename|
    doc = Nokogiri::XML(File.read(filename), nil, "UTF-8") { |x| x.noblanks }

    xml_node = doc.at_xpath("/recording/id")
    record_id = xml_node.content

    # publish the news to redis
    BigBlueButton.redis_publisher.put_message("deleted", record_id)
    # give some time to trigger the redis message
    sleep 0.2
  end
end
