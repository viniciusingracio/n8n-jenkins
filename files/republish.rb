# encoding: UTF-8

require 'fileutils'
require 'nokogiri'

to_check = [
  "778fc169bc73c89a6bc0b201dafcbf3ab199e69c-1561640616051",
  "a26aaea80926b42958fed7cc856a8172d8c693dd-1561641096598",
  "b9aab59f17b692f4e10802c3a9c47a2ae489f89d-1561644218793",
  "319c2c4b03259e5c499af38ae4316bddcb007c6d-1561640049609",
  "5df70febc8975637e6e0b5dba0fb6479ea991b81-1561642123843",
  "fa0e105a379dfa2c5f0ea4e261f676fdae8a515d-1561641227857",
  "8c99c9e1aaea40e7fad9f16483031ba90dd09546-1561648097451",
  "8e99a0f09b4fab11651b8ed167c44bf2196dab02-1561638503815",
  "adb34db8481b665c5e114b661741c20af59c8af5-1561644899853",
  "c02513c06a1cf5b8ff27ef791398fa6464532b5a-1561643095426",
  "f3f0b85aa075cd044995b2443a71ae704f065a8d-1561647949361"
]

to_check.each do |record_id|
  path = "/var/bigbluebutton/deleted/mconf_encrypted/#{record_id}"
  next if ! File.exists?(path)

  metadata_xml = "#{path}/metadata.xml"
  FileUtils.cp metadata_xml, "#{metadata_xml}.orig" if ! File.exists? "#{metadata_xml}.orig"

  metadata = Nokogiri::XML(File.open(metadata_xml)) { |x| x.noblanks }
  metadata.at_xpath("/recording/state").content = "published"
  metadata.at_xpath("/recording/published").content = "true"

  xml_file = File.new(metadata_xml, "w")
  xml_file.write(metadata.to_xml(:indent => 2))
  xml_file.close

  FileUtils.mv path, "/var/bigbluebutton/published/mconf_encrypted/#{record_id}"
end
