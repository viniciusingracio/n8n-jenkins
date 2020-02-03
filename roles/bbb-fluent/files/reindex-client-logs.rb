# encoding: UTF-8

# ruby reindex-client-logs.rb | tee -a /var/log/nginx/html5-client-reindex.log > /dev/null

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

Signal.trap("PIPE", "EXIT")

`ls -tr1 /var/log/nginx/html5-client.log.*`.split("\n").each do |log_file|
    if File.extname(log_file) == ".gz"
        lines = `zcat #{log_file}`.split("\n")
    else
        lines = File.readlines(log_file)
    end
    lines.each { |line| puts line }
end
