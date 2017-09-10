id = 'themis-finals'
h = ::ChefCookbook::Instance::Helper.new(node)

basedir = ::File.join(node[id]['basedir'], 'backend')
url_repository = "https://github.com/#{node[id]['backend']['github_repository']}"

directory basedir do
  owner h.instance_user
  group h.instance_group
  mode 0755
  recursive true
  action :create
end

if node.chef_environment.start_with?('development')
  ssh_private_key h.instance_user
  ssh_known_hosts_entry 'github.com'
  url_repository = "git@github.com:#{node[id]['backend']['github_repository']}.git"
end

git2 basedir do
  url url_repository
  branch node[id]['backend']['revision']
  user h.instance_user
  group h.instance_group
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
    git_config "git-config #{key} at #{basedir}" do
      key key
      value value
      scope 'local'
      path basedir
      user h.instance_user
      action :set
    end
  end
end

rbenv_execute "Install dependencies at #{basedir}" do
  command 'bundle'
  ruby_version node['themis-finals-utils']['ruby']['version']
  cwd basedir
  user h.instance_user
  group h.instance_group
end

config_file = ::File.join(basedir, 'config.rb')

template config_file do
  source 'config.rb.erb'
  user h.instance_user
  group h.instance_group
  mode 0644
  variables(
    internal_networks: node[id]['config']['internal_networks'],
    contest: node[id]['config']['contest'],
    teams: node[id]['config']['teams'],
    services: node[id]['config']['services']
  )
  action :create
end

dotenv_file = ::File.join(basedir, '.env')

template dotenv_file do
  source 'dotenv.erb'
  user h.instance_user
  group h.instance_group
  mode 0600
  variables(
    redis_host: node['latest-redis']['listen']['address'],
    redis_port: node['latest-redis']['listen']['port'],
    pg_host: node[id]['postgres']['host'],
    pg_port: node[id]['postgres']['port'],
    pg_username: node[id]['postgres']['username'],
    pg_password: data_bag_item('postgres', node.chef_environment)['credentials'][node[id]['postgres']['username']],
    pg_database: node[id]['postgres']['dbname'],
    stream_redis_db: node[id]['stream']['redis_db'],
    queue_redis_db: node[id]['backend']['queue']['redis_db'],
    stream_redis_channel_namespace: node[id]['stream']['redis_channel_namespace']
  )
  action :create
end

script_dir = ::File.join(node[id]['basedir'], 'script')
dump_db_script = ::File.join(script_dir, 'dump_main_db')

template dump_db_script do
  source 'dump_db.sh.erb'
  owner h.instance_user
  group h.instance_group
  mode 0775
  variables(
    pg_host: node[id]['postgres']['host'],
    pg_port: node[id]['postgres']['port'],
    pg_username: node[id]['postgres']['username'],
    pg_password: data_bag_item('postgres', node.chef_environment)['credentials'][node[id]['postgres']['username']],
    pg_dbname: node[id]['postgres']['dbname']
  )
end

namespace = "#{node[id]['supervisor_namespace']}.master"

supervisor_service "#{namespace}.queue" do
  command 'sh script/queue'
  process_name 'queue-%(process_num)s'
  numprocs node[id]['backend']['queue']['processes']
  numprocs_start 0
  priority 300
  autostart node[id]['autostart']
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup true
  killasgroup true
  user h.instance_user
  redirect_stderr false
  stdout_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.queue-%(process_num)s-stdout.log")
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.queue-%(process_num)s-stderr.log")
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  environment(
    'PATH' => '/usr/bin/env:/opt/rbenv/shims:%(ENV_PATH)s',
    'INSTANCE' => '%(process_num)s',
    'LOG_LEVEL' => node[id]['debug'] ? 'DEBUG' : 'INFO',
    'STDOUT_SYNC' => node[id]['debug'],
    'REDIS_HOST' => node['latest-redis']['listen']['address'],
    'REDIS_PORT' => node['latest-redis']['listen']['port'],
    'PG_HOST' => node[id]['postgres']['host'],
    'PG_PORT' => node[id]['postgres']['port'],
    'PG_USERNAME' => node[id]['postgres']['username'],
    'PG_PASSWORD' => data_bag_item('postgres', node.chef_environment)['credentials'][node[id]['postgres']['username']],
    'PG_DATABASE' => node[id]['postgres']['dbname'],
    'THEMIS_FINALS_FLAG_GENERATOR_SECRET' => data_bag_item('themis-finals', node.chef_environment)['flag_generator_secret'],
    'THEMIS_FINALS_MASTER_FQDN' => node[id]['fqdn'],
    'THEMIS_FINALS_MASTER_KEY' => data_bag_item('themis-finals', node.chef_environment)['keys']['master'],
    'THEMIS_FINALS_KEY_NONCE_SIZE' => node[id]['key_nonce_size'],
    'THEMIS_FINALS_AUTH_TOKEN_HEADER' => node[id]['auth_token_header'],
    'THEMIS_FINALS_STREAM_REDIS_DB' => node[id]['stream']['redis_db'],
    'THEMIS_FINALS_QUEUE_REDIS_DB' => node[id]['backend']['queue']['redis_db'],
    'THEMIS_FINALS_STREAM_REDIS_CHANNEL_NAMESPACE' => node[id]['stream']['redis_channel_namespace'],
    'THEMIS_FINALS_FLAG_SIGN_KEY_PRIVATE' => data_bag_item('themis-finals', node.chef_environment)['sign_key']['private'].gsub("\n", "\\n"),
    'THEMIS_FINALS_FLAG_WRAP_PREFIX' => node[id]['flag_wrap']['prefix'],
    'THEMIS_FINALS_FLAG_WRAP_SUFFIX' => node[id]['flag_wrap']['suffix']
  )
  directory basedir
  serverurl 'AUTO'
  action :enable
end

template ::File.join(script_dir, 'tail-queue-stdout') do
  source 'tail.sh.erb'
  owner h.instance_user
  group h.instance_group
  mode 0755
  variables(
    files: ::Range.new(0, node[id]['backend']['queue']['processes'], true).map do |ndx|
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.queue-#{ndx}-stdout.log")
    end
  )
  action :create
end

template ::File.join(script_dir, 'tail-queue-stderr') do
  source 'tail.sh.erb'
  owner h.instance_user
  group h.instance_group
  mode 0755
  variables(
    files: ::Range.new(0, node[id]['backend']['queue']['processes'], true).map do |ndx|
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.queue-#{ndx}-stderr.log")
    end
  )
  action :create
end

supervisor_service "#{namespace}.scheduler" do
  command 'sh script/scheduler'
  process_name 'scheduler'
  numprocs 1
  numprocs_start 0
  priority 300
  autostart node[id]['autostart']
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup true
  killasgroup true
  user h.instance_user
  redirect_stderr false
  stdout_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.scheduler-stdout.log")
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.scheduler-stderr.log")
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  environment(
    'PATH' => '/usr/bin/env:/opt/rbenv/shims:%(ENV_PATH)s',
    'LOG_LEVEL' => node[id]['debug'] ? 'DEBUG' : 'INFO',
    'STDOUT_SYNC' => node[id]['debug'],
    'REDIS_HOST' => node['latest-redis']['listen']['address'],
    'REDIS_PORT' => node['latest-redis']['listen']['port'],
    'PG_HOST' => node[id]['postgres']['host'],
    'PG_PORT' => node[id]['postgres']['port'],
    'PG_USERNAME' => node[id]['postgres']['username'],
    'PG_PASSWORD' => data_bag_item('postgres', node.chef_environment)['credentials'][node[id]['postgres']['username']],
    'PG_DATABASE' => node[id]['postgres']['dbname'],
    'THEMIS_FINALS_MASTER_FQDN' => node[id]['fqdn'],
    'THEMIS_FINALS_STREAM_REDIS_DB' => node[id]['stream']['redis_db'],
    'THEMIS_FINALS_QUEUE_REDIS_DB' => node[id]['backend']['queue']['redis_db'],
    'THEMIS_FINALS_STREAM_REDIS_CHANNEL_NAMESPACE' => node[id]['stream']['redis_channel_namespace']
  )
  directory basedir
  serverurl 'AUTO'
  action :enable
end

template ::File.join(script_dir, 'tail-scheduler-stdout') do
  source 'tail.sh.erb'
  owner h.instance_user
  group h.instance_group
  mode 0755
  variables(
    files: [
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.scheduler-stdout.log")
    ]
  )
  action :create
end

template ::File.join(script_dir, 'tail-scheduler-stderr') do
  source 'tail.sh.erb'
  owner h.instance_user
  group h.instance_group
  mode 0755
  variables(
    files: [
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.scheduler-stderr.log")
    ]
  )
  action :create
end

team_logo_dir = ::File.join(node[id]['basedir'], 'team_logo')

supervisor_service "#{namespace}.server" do
  command 'sh script/server'
  process_name 'server-%(process_num)s'
  numprocs node[id]['backend']['server']['processes']
  numprocs_start 0
  priority 300
  autostart node[id]['autostart']
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup true
  killasgroup true
  user h.instance_user
  redirect_stderr false
  stdout_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.server-%(process_num)s-stdout.log")
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.server-%(process_num)s-stderr.log")
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  environment(
    'PATH' => '/usr/bin/env:/opt/rbenv/shims:%(ENV_PATH)s',
    'HOST' => '127.0.0.1',
    'PORT' => node[id]['backend']['server']['port_range_start'],
    'INSTANCE' => '%(process_num)s',
    'LOG_LEVEL' => node[id]['debug'] ? 'DEBUG' : 'INFO',
    'STDOUT_SYNC' => node[id]['debug'],
    'RACK_ENV' => node.chef_environment,
    'REDIS_HOST' => node['latest-redis']['listen']['address'],
    'REDIS_PORT' => node['latest-redis']['listen']['port'],
    'PG_HOST' => node[id]['postgres']['host'],
    'PG_PORT' => node[id]['postgres']['port'],
    'PG_USERNAME' => node[id]['postgres']['username'],
    'PG_PASSWORD' => data_bag_item('postgres', node.chef_environment)['credentials'][node[id]['postgres']['username']],
    'PG_DATABASE' => node[id]['postgres']['dbname'],
    'THEMIS_FINALS_TEAM_LOGO_DIR' => team_logo_dir,
    'THEMIS_FINALS_MASTER_FQDN' => node[id]['fqdn'],
    'THEMIS_FINALS_CHECKER_KEY' => data_bag_item('themis-finals', node.chef_environment)['keys']['checker'],
    'THEMIS_FINALS_KEY_NONCE_SIZE' => node[id]['key_nonce_size'],
    'THEMIS_FINALS_AUTH_TOKEN_HEADER' => node[id]['auth_token_header'],
    'THEMIS_FINALS_STREAM_REDIS_DB' => node[id]['stream']['redis_db'],
    'THEMIS_FINALS_QUEUE_REDIS_DB' => node[id]['backend']['queue']['redis_db'],
    'THEMIS_FINALS_STREAM_REDIS_CHANNEL_NAMESPACE' => node[id]['stream']['redis_channel_namespace'],
    'THEMIS_FINALS_FLAG_SIGN_KEY_PUBLIC' => data_bag_item('themis-finals', node.chef_environment)['sign_key']['public'].gsub("\n", "\\n"),
  )
  directory basedir
  serverurl 'AUTO'
  action :enable
end

template ::File.join(script_dir, 'tail-server-stdout') do
  source 'tail.sh.erb'
  owner h.instance_user
  group h.instance_group
  mode 0755
  variables(
    files: ::Range.new(0, node[id]['backend']['server']['processes'], true).map do |ndx|
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.server-#{ndx}-stdout.log")
    end
  )
  action :create
end

template ::File.join(script_dir, 'tail-server-stderr') do
  source 'tail.sh.erb'
  owner h.instance_user
  group h.instance_group
  mode 0755
  variables(
    files: ::Range.new(0, node[id]['backend']['server']['processes'], true).map do |ndx|
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.server-#{ndx}-stderr.log")
    end
  )
  action :create
end

