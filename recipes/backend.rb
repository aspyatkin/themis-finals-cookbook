id = 'themis-finals'
instance = ::ChefCookbook::Instance::Helper.new(node)
secret = ::ChefCookbook::Secret::Helper.new(node)
h = ::ChefCookbook::Themis::Finals::Helper.new(node)

url_repository = "https://github.com/#{node[id]['backend']['github_repository']}"

directory h.backend_dir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

if node.chef_environment.start_with?('development')
  ssh_private_key instance.user
  ssh_known_hosts_entry 'github.com'
  url_repository = "git@github.com:#{node[id]['backend']['github_repository']}.git"
end

git2 h.backend_dir do
  url url_repository
  branch node[id]['backend']['revision']
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
    git_config "git-config #{key} at #{h.backend_dir}" do
      key key
      value value
      scope 'local'
      path h.backend_dir
      user instance.user
      action :set
    end
  end
end

rbenv_execute "Install dependencies at #{h.backend_dir}" do
  command 'bundle'
  ruby_version node['themis-finals-utils']['ruby']['version']
  cwd h.backend_dir
  user instance.user
  group instance.group
end

dotenv_file = ::File.join(h.backend_dir, '.env')

template dotenv_file do
  source 'dotenv.erb'
  user instance.user
  group instance.group
  mode 0600
  variables lazy {
    {
      env: h.env
    }
  }
  action :create
end

dump_db_script = ::File.join(h.script_dir, 'dump_main_db')

template dump_db_script do
  source 'dump_db.sh.erb'
  owner instance.user
  group instance.group
  mode 0775
  variables lazy {
    {
      pg_host: h.postgres_host,
      pg_port: h.postgres_port,
      pg_username: node[id]['postgres']['username'],
      pg_password: secret.get("postgres:password:#{node[id]['postgres']['username']}"),
      pg_dbname: node[id]['postgres']['dbname']
    }
  }
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
  user instance.user
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
  environment lazy {
    {
      'PATH' => '/usr/bin/env:/opt/rbenv/shims:%(ENV_PATH)s',
      'INSTANCE' => '%(process_num)s',
      'LOG_LEVEL' => node[id]['debug'] ? 'DEBUG' : 'INFO',
      'STDOUT_SYNC' => node[id]['debug']
    }.merge(h.env)
  }
  directory h.backend_dir
  serverurl 'AUTO'
  action :enable
end

template ::File.join(h.script_dir, 'tail-queue-stdout') do
  source 'tail.sh.erb'
  owner instance.user
  group instance.group
  mode 0755
  variables(
    files: ::Range.new(0, node[id]['backend']['queue']['processes'], true).map do |ndx|
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.queue-#{ndx}-stdout.log")
    end
  )
  action :create
end

template ::File.join(h.script_dir, 'tail-queue-stderr') do
  source 'tail.sh.erb'
  owner instance.user
  group instance.group
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
  user instance.user
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
  environment lazy {
    {
      'PATH' => '/usr/bin/env:/opt/rbenv/shims:%(ENV_PATH)s',
      'LOG_LEVEL' => node[id]['debug'] ? 'DEBUG' : 'INFO',
      'STDOUT_SYNC' => node[id]['debug']
    }.merge(h.env)
  }
  directory h.backend_dir
  serverurl 'AUTO'
  action :enable
end

template ::File.join(h.script_dir, 'tail-scheduler-stdout') do
  source 'tail.sh.erb'
  owner instance.user
  group instance.group
  mode 0755
  variables(
    files: [
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.scheduler-stdout.log")
    ]
  )
  action :create
end

template ::File.join(h.script_dir, 'tail-scheduler-stderr') do
  source 'tail.sh.erb'
  owner instance.user
  group instance.group
  mode 0755
  variables(
    files: [
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.scheduler-stderr.log")
    ]
  )
  action :create
end

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
  user instance.user
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
  environment lazy {
    {
      'PATH' => '/usr/bin/env:/opt/rbenv/shims:%(ENV_PATH)s',
      'HOST' => '127.0.0.1',
      'PORT' => node[id]['backend']['server']['port_range_start'],
      'INSTANCE' => '%(process_num)s',
      'LOG_LEVEL' => node[id]['debug'] ? 'DEBUG' : 'INFO',
      'STDOUT_SYNC' => node[id]['debug'],
      'RACK_ENV' => node.chef_environment
    }.merge(h.env)
  }
  directory h.backend_dir
  serverurl 'AUTO'
  action :enable
end

template ::File.join(h.script_dir, 'tail-server-stdout') do
  source 'tail.sh.erb'
  owner instance.user
  group instance.group
  mode 0755
  variables(
    files: ::Range.new(0, node[id]['backend']['server']['processes'], true).map do |ndx|
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.server-#{ndx}-stdout.log")
    end
  )
  action :create
end

template ::File.join(h.script_dir, 'tail-server-stderr') do
  source 'tail.sh.erb'
  owner instance.user
  group instance.group
  mode 0755
  variables(
    files: ::Range.new(0, node[id]['backend']['server']['processes'], true).map do |ndx|
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.server-#{ndx}-stderr.log")
    end
  )
  action :create
end
