#!/usr/bin/env ruby

require 'fileutils'


def log(message)
  puts "\033[0;31m#{message}\033[0m"
end


def proxy_already_running?
  netstat_response = `netstat -an | grep 9150`
  # puts "=== netstat_response: #{netstat_response}"
  if netstat_response == ''
    return false
  end
  curl_response = `curl -IkL --connect-timeout 5 -X HEAD -x socks://localhost:9150 https://www.google.com 2>/dev/null`
  # puts "=== curl_response: #{curl_response}"
  curl_response.lines[0] =~ /(?:\b200\b)|(?:\b302\b)/i
end


def launch_browser
  fork do
    log '=== opening incognito chrome browser'
    user_data_dir = "#{File.absolute_path(File.dirname(__FILE__))}/user-data"
    FileUtils.mkdir_p(user_data_dir)
    `open -W -n -a "Google Chrome" --args --incognito --user-data-dir="#{user_data_dir}" --proxy-server=socks://localhost:9150 https://check.torproject.org/`
    log '=== stopping tor after incognito chrome browser closed'
    `docker stop tor_instance`
    log "\n=== tor successfully stopped\n"
    exit 0
  end
  # How to determine if any remaining browser procs are running:
  #   $ ps -ef | grep 'Contents\/MacOS\/Google Chrome --incognito --user-data-dir=#{user_data_dir.gsub('/', '\/')}'
end


def launch_browser_when_proxy_ready
  fork do
    10.times do |i|
      if proxy_already_running?
        launch_browser
        exit 0
      else
        log "--- waiting for tor to make connection (#{10-i} more tries)"
        sleep 5
      end
    end
    log '--- giving up on tor connection - skipping launch of chrome browser'
    exit 0
  end
end


Signal.trap("INT") { # trap ctrl-c
  container_id = `docker ps -q -f name=tor_instance`
  if container_id
    log '=== stopping tor due to ctrl-c'
    `docker stop tor_instance`
    log "\n=== tor successfully stopped\n"
  end
  exit 0
  # TODO: kill off chrome by terminating Chrome instance that is child proc of this script
}


if proxy_already_running?
  launch_browser
else
  launch_browser_when_proxy_ready
  log '=== synchronizing docker date/time with host'
  date = `date -u +%m%d%H%M%Y`
  log '=== docker date/time = ' + `docker run --rm --privileged nagev/tor date -u #{date}`
  log '=== starting tor'
  docker_response = `docker run -d --rm --name tor_instance -p 9150:9150 nagev/tor 2>&1`
  if docker_response =~ /Conflict\. The container name "\/tor_instance" is already in use by container ([a-f0-9]+)\./
    log '=== removing existing stopped tor docker container'
    `docker rm #{$1}`
    log '=== starting tor (trying again)'
    docker_response = `docker run -d --rm --name tor_instance -p 9150:9150 nagev/tor 2>&1`
  end
  exec("docker logs -f #{docker_response}")
end



# TODO: maybe run docker container as non-root user?
#   see: https://forums.docker.com/t/swiching-between-root-and-non-root-users-from-interactive-console/2269/2
#   also see how sabnzbd Dockerfile handled it: https://hub.docker.com/r/sabnzbd/sabnzbd/

# TODO: use --ash-host-window-bounds chrome arg to set window position/size for demo video
#   see: http://peter.sh/experiments/chromium-command-line-switches/

# TODO: use latest tag for tor docker image and pull latest image before launch
