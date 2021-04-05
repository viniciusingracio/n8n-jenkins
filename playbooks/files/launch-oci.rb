# encoding: UTF-8

# Install dependencies with:
# sudo gem install optimist
#
# Put this file under /usr/local/share/mconf/launch-oci.rb
#
# Run with:
# ruby /usr/local/share/mconf/launch-oci.rb --num ${NUM_INSTANCES} --compartments ocid1.compartment.oc1..aaaaaaaaaeii7w32pohsveeuiwqc4jsncffqmotabphsfpzczs3uklrdehgq,ocid1.compartment.oc1..aaaaaaaaz4zkqdshyrgmwa4jsp3yrzq2erbsic4fswzuvgtiojkxq3fiecbq
#
# Schedule it to:
# TZ=America/Sao_Paulo
# H(30-59)/10 6 * * 1-5

require 'json'
require 'logger'
require 'optimist'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

opts = Optimist::options do
  opt :compartments, "Comma-separated compartment", :type => :string, :required => true
  opt :num, "Number of instances", :type => :integer, :required => true
end

logger = Logger.new(STDOUT)

instances = []
opts[:compartments].split(",").each do |compartment|
  command = "oci compute instance list --compartment-id #{compartment} --auth instance_principal --all"
  logger.info "Running: #{command}"
  output = `#{command}`
  if $?.success?
    instances += JSON.parse(output)["data"]
  else
    logger.error "Couldn't fetch instances from compartment #{compartment}, output:\n#{output}"
    redo
  end
end

instances.sort_by! { |i| i["display-name"] }

instances.first(opts[:num]).each do |instance|
  name = instance["display-name"]
  state = instance["lifecycle-state"]
  case state
  when "STOPPED"
    logger.info "#{name} stopped, launch!"
    command = "oci compute instance action --action START --instance-id #{instance["id"]} --auth instance_principal"
    logger.info "Running: #{command}"
    output = `#{command}`
    if $?.success?
      launch = JSON.parse(output)["data"]
      logger.info "New state for #{name} is #{launch["lifecycle-state"]}"
    else
      logger.warn "Execution didn't return a valid output while starting #{name}, output:\n#{output}"
    end
  when "RUNNING"
    logger.info "#{name} is already running"
  else
    logger.info "#{name} state is #{state}"
  end
end
