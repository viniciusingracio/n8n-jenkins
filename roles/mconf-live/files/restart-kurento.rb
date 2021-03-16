#!/usr/bin/ruby

require 'docker'

# Install dependencies:
# gem install docker-api

all_containers = Docker::Container.all(:all => true)

kurento_containers = all_containers.select{ |container| container.info["Names"].first.match(/^\/kurento_\d+/) }

# this procedure will track the state of kurento, and restart it after 5 minutes unhealthy
kurento_containers.each do |container|
  container_name = container.info["Names"].first
  container_healthy = ! ( container.info["State"] != "running" || container.info["Status"].match(/ \(unhealthy\)$/) )

  unhealthy_filename = "/tmp/#{container_name}-unhealthy"
  if container_healthy
    FileUtils.rm_f(unhealthy_filename) if File.exists?(unhealthy_filename)
  else
    if File.exists?(unhealthy_filename)
      if (Time.now - File.ctime(unhealthy_filename)).to_i > 180
        begin
          container.restart
          FileUtils.rm_f(unhealthy_filename)
        rescue Exception => e
          # if something goes wrong on restarting the container,
          # ignore it but do not remove the unhealthy file
        end
      else
        # it means that unhealthy file was created less than 3 minutes ago
      end
    else
      FileUtils.touch(unhealthy_filename)
    end
  end
end
