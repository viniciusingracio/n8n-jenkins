#!/usr/bin/ruby

require 'net/http'
require 'digest/sha1'
require 'benchmark'

# Manage BBB properties such as server address and salt.
# These informations can be loaded from file (bigbluebutton.properties) or
# externally set (for instance, from command line).
class BBBProperties
  def self.load_properties_from_file()
    servlet_dir = File.exists?("/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties") ? "/usr/share/bbb-web" : "/var/lib/tomcat7/webapps/bigbluebutton"
    @@properties = Hash[File.read("#{servlet_dir}/WEB-INF/classes/bigbluebutton.properties", :encoding => "ISO-8859-1:UTF-8").scan(/(.+?)=(.+)/)]
  end

  def self.load_properties_from_cli(server_url, salt)
    @@properties = Hash.new(0)
    @@properties['bigbluebutton.web.serverURL'] = server_url
    @@properties['securitySalt'] = salt
  end

  def self.server_url
    @@server_url ||= get_properties 'bigbluebutton.web.serverURL'
  end

  def self.security_salt
    @@security_salt ||= get_properties 'securitySalt'
  end

  def self.get_properties(property)
    begin
      @@properties[property]
    rescue Errno::ENOENT => errno
      puts "error: #{errno}"
      exit
    end
  end

  private_class_method :get_properties
end

# Build URIs to different resources available in the BBB server.
class URIBuilder
  def self.server_url=(server_url)
    @@server_url = server_url
  end

  def self.api_uri
    @@api_uri ||= build_uri "/bigbluebutton/api"
  end

  def self.demo_uri
    @@demo_uri ||= build_uri "/demo/demo1.jsp"
  end

  def self.client_uri
    @@client_uri ||= build_uri "client/conf/config.xml"
  end

  def self.api_method_uri(method, params=nil)
    get_security(method, params) do |params, checksum|
      "bigbluebutton/api/#{method}?#{params}&checksum=#{checksum}"
    end
  end

  def self.build_uri(path)
    begin
      URI::join(@@server_url, path)
    rescue ArgumentError => errno
      puts "error: #{errno}"
      exit
    end
  end

  def self.get_security(method, params=nil)
    params ||= "random=#{rand(99999)}"
    checksum = Digest::SHA1.hexdigest "#{method}#{params}#{BBBProperties.security_salt}"
    build_uri yield(params, checksum)
  end

  private_class_method :build_uri, :get_security
end

# HTTP connection manager to retrieve informations from the BBB server.
class HTTPRequester
  attr_accessor :ssl_enabled

  def initialize(ssl_enabled = false)
    @ssl_enabled = ssl_enabled
  end

  def get_response(uri)
    uri.scheme, uri.port = @ssl_enabled ? ['https',443] : ['http',80]
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = @ssl_enabled

    # It never raises an exception
    http.get(uri.request_uri)
  end

  def get_response_code(*args)
    get_response(*args).code
  end

  def is_responding?(service)
    case service
    when 'bbb'
      service_uri = URIBuilder.api_uri
    when 'demo'
      service_uri = URIBuilder.demo_uri
    when 'client'
      service_uri = URIBuilder.client_uri
    else
      'Invalid service'
    end

    get_response(service_uri).code == '200'
  end
end

class Hash
  # return a copy of the hash, where values are evaluated as Integer and Float
  def evaluate_values
    Hash[self.map{|k,v| [k, (Integer(v) rescue v)]}]
  end

  class << self
    def from_xml(xml_io)
      begin
        result = Nokogiri::XML(xml_io)
        return { result.root.name.to_sym => xml_node_to_hash(result.root)}
      rescue Exception => e
        # raise your custom exception here
      end
    end

    def xml_node_to_hash(node)
      # If we are at the root of the document, start the hash
      if node.element?
        result_hash = {}
        if node.attributes != {}
          attributes = {}
          node.attributes.keys.each do |key|
            attributes[node.attributes[key].name.to_sym] = node.attributes[key].value
          end
        end
        if node.children.size > 0
          node.children.each do |child|
            result = xml_node_to_hash(child)

            if child.name == "text"
              unless child.next_sibling || child.previous_sibling
                return result unless attributes
                result_hash[child.name.to_sym] = result
              end
            elsif result_hash[child.name.to_sym]

              if result_hash[child.name.to_sym].is_a?(Object::Array)
                 result_hash[child.name.to_sym] << result
              else
                 result_hash[child.name.to_sym] = [result_hash[child.name.to_sym]] << result
              end
            else
              result_hash[child.name.to_sym] = result
            end
          end
          if attributes
             #add code to remove non-data attributes e.g. xml schema, namespace here
             #if there is a collision then node content supersets attributes
             result_hash = attributes.merge(result_hash)
          end
          return result_hash
        else
          return attributes
        end
      else
        return node.content.to_s
      end
    end
  end
end
