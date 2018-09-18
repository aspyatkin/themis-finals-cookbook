require 'json'
id = 'themis-finals'
instance = ::ChefCookbook::Instance::Helper.new(node)
secret = ::ChefCookbook::Secret::Helper.new(node)
h = ::ChefCookbook::Themis::Finals::Helper.new(node)

url_repository = "https://github.com/#{node[id]['stream']['github_repository']}"

directory h.stream_dir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

if node.chef_environment.start_with?('development')
  ssh_private_key instance.user
  ssh_known_hosts_entry 'github.com'
  url_repository = "git@github.com:#{node[id]['stream']['github_repository']}.git"
end

git2 h.stream_dir do
  url url_repository
  branch node[id]['stream']['revision']
  user instance.user
  group instance.group
  action :create
end

if node.chef_environment.start_with?('development')
  git_data_bag_item = nil
  begin
    git_data_bag_item = data_bag_item('git', node.chef_environment)
  rescue
    ::Chef::Log.warn('Check whether git data bag exists!')
  end

  git_options = git_data_bag_item.nil? ? {} : git_data_bag_item.to_hash.fetch('config', {})

  git_options.each do |key, value|
    git_config "git-config #{key} at #{h.stream_dir}" do
      key key
      value value
      scope 'local'
      path h.stream_dir
      user instance.user
      action :set
    end
  end
end

yarn_install h.stream_dir do
  user instance.user
  action :run
end

yarn_run "Build scripts at #{h.stream_dir}" do
  script 'build'
  user instance.user
  dir h.stream_dir
  action :run
end

config = {
  network: {
    internal: node['themis-finals']['config']['internal_networks'],
    team: node['themis-finals']['config']['teams'].values.map { |x| x['network']}
  }
}

config_file = ::File.join(h.stream_dir, 'config.json')

file config_file do
  owner instance.user
  group instance.group
  mode 0644
  content ::JSON.pretty_generate(config)
  action :create
end

namespace = "#{node[id]['supervisor_namespace']}.master"

supervisor_service "#{namespace}.stream" do
  command 'node ./dist/server.js'
  process_name 'stream-%(process_num)s'
  numprocs node[id]['stream']['processes']
  numprocs_start 0
  priority 300
  autostart node[id]['autostart']
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup false
  killasgroup false
  user instance.user
  redirect_stderr false
  stdout_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.stream-%(process_num)s-stdout.log")
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.stream-%(process_num)s-stderr.log")
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  environment lazy {
    {
      'HOST' => '127.0.0.1',
      'PORT' => node[id]['stream']['port_range_start'],
      'INSTANCE' => '%(process_num)s',
      'LOG_LEVEL' => node[id]['debug'] ? 'debug' : 'info',
      'REDIS_HOST' => h.redis_host,
      'REDIS_PORT' => h.redis_port,
      'REDIS_PASSWORD' => secret.get(
        'redis:password',
        required: false,
        default: nil,
        prefix_fqdn: node[id]['redis_secret']['prefix_fqdn'].nil? ? node['secret']['prefix_fqdn'] : node[id]['redis_secret']['prefix_fqdn']
      ),
      'PG_HOST' => h.postgres_host,
      'PG_PORT' => h.postgres_port,
      'PG_USERNAME' => node[id]['postgres']['username'],
      'PG_PASSWORD' => secret.get(
        "postgres:password:#{node[id]['postgres']['username']}",
        prefix_fqdn: node[id]['postgres_secret']['prefix_fqdn'].nil? ? node['secret']['prefix_fqdn'] : node[id]['postgres_secret']['prefix_fqdn']
      ),
      'PG_DATABASE' => node[id]['postgres']['dbname'],
      'THEMIS_FINALS_STREAM_REDIS_DB' => node[id]['stream']['redis_db'],
      'THEMIS_FINALS_STREAM_REDIS_CHANNEL_NAMESPACE' => node[id]['stream']['redis_channel_namespace']
    }
  }
  directory h.stream_dir
  serverurl 'AUTO'
  action :enable
end

template ::File.join(h.script_dir, 'tail-stream-stdout') do
  source 'tail.sh.erb'
  owner instance.user
  group instance.group
  mode 0755
  variables(
    files: ::Range.new(0, node[id]['stream']['processes'], true).map do |ndx|
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.stream-#{ndx}-stdout.log")
    end
  )
  action :create
end

template ::File.join(h.script_dir, 'tail-stream-stderr') do
  source 'tail.sh.erb'
  owner instance.user
  group instance.group
  mode 0755
  variables(
    files: ::Range.new(0, node[id]['stream']['processes'], true).map do |ndx|
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.stream-#{ndx}-stderr.log")
    end
  )
  action :create
end
