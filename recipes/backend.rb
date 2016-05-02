id = 'themis-finals'

basedir = ::File.join node[id][:basedir], 'backend'
url_repository = "https://github.com/#{node[id][:backend][:github_repository]}"

directory basedir do
  owner node[id][:user]
  group node[id][:group]
  mode 0755
  recursive true
  action :create
end

if node.chef_environment.start_with? 'development'
  ssh_data_bag_item = nil
  begin
    ssh_data_bag_item = data_bag_item('ssh', node.chef_environment)
  rescue
  end

  ssh_key_map = (ssh_data_bag_item.nil?) ? {} : ssh_data_bag_item.to_hash.fetch('keys', {})

  if ssh_key_map.size > 0
    url_repository = "git@github.com:#{node[id][:backend][:github_repository]}.git"
    ssh_known_hosts_entry 'github.com'
  end
end

git2 basedir do
  url url_repository
  branch node[id][:backend][:revision]
  user node[id][:user]
  group node[id][:group]
  action :create
end

if node.chef_environment.start_with? 'development'
  git_data_bag_item = nil
  begin
    git_data_bag_item = data_bag_item('git', node.chef_environment)
  rescue
  end

  git_options = (git_data_bag_item.nil?) ? {} : git_data_bag_item.to_hash.fetch('config', {})

  git_options.each do |key, value|
    git_config "git-config #{key} at #{basedir}" do
      key key
      value value
      scope 'local'
      path basedir
      user node[id][:user]
      action :set
    end
  end
end

rbenv_execute "Install dependencies at #{basedir}" do
  command 'bundle'
  ruby_version node[id][:ruby][:version]
  cwd basedir
  user node[id][:user]
  group node[id][:group]
end

aws_data_bag_item = nil
begin
  aws_data_bag_item = data_bag_item('aws', node.chef_environment)
rescue
end

aws_credentials = (aws_data_bag_item.nil?) ? {} : aws_data_bag_item.to_hash.fetch('credentials', {})

post_scoreboard = node[id][:post_scoreboard] && aws_credentials.key?('access_key_id') && aws_credentials.key?('secret_access_key') && aws_credentials.key?('bucket') && aws_credentials.key?('region')

if post_scoreboard
  dotenv_file = ::File.join basedir, '.env'

  template dotenv_file do
    source 'dotenv.erb'
    user node[id][:user]
    group node[id][:group]
    mode 0600
    variables(
      aws_access_key_id: aws_credentials.fetch('access_key_id', nil),
      aws_secret_access_key: aws_credentials.fetch('secret_access_key', nil),
      aws_bucket: aws_credentials.fetch('bucket', nil),
      aws_region: aws_credentials.fetch('region', nil),
      redis_host: node[id][:redis][:listen][:address],
      redis_port: node[id][:redis][:listen][:port],
      redis_db: node[id][:redis][:db],
      pg_host: node[id][:postgres][:listen][:address],
      pg_port: node[id][:postgres][:listen][:port],
      pg_username: node[id][:postgres][:username],
      pg_password: data_bag_item('postgres', node.chef_environment)['credentials'][node[id][:postgres][:username]],
      pg_database: node[id][:postgres][:dbname]
    )
    action :create
  end
end

rbenv_root = node[:rbenv][:root_path]
logs_basedir = ::File.join node[id][:basedir], 'logs'

supervisor_service "#{node[id][:supervisor][:namespace]}.queue" do
  command "#{rbenv_root}/shims/bundle exec ruby queue.rb"
  process_name 'queue-%(process_num)s'
  numprocs node[id][:backend][:queue][:processes]
  numprocs_start 0
  priority 300
  autostart false
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup false
  killasgroup false
  user node[id][:user]
  redirect_stderr false
  stdout_logfile ::File.join logs_basedir, 'queue-%(process_num)s-stdout.log'
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join logs_basedir, 'queue-%(process_num)s-stderr.log'
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  environment(
    'CTFTIME_SCOREBOARD' => post_scoreboard,
    'AWS_ACCESS_KEY_ID' => aws_credentials.fetch('access_key_id', nil),
    'AWS_SECRET_ACCESS_KEY' => aws_credentials.fetch('secret_access_key', nil),
    'AWS_REGION' => aws_credentials.fetch('region', nil),
    'AWS_BUCKET' => aws_credentials.fetch('bucket', nil),
    'APP_INSTANCE' => '%(process_num)s',
    'LOG_LEVEL' => node[id][:backend][:debug] ? 'DEBUG' : 'INFO',
    'STDOUT_SYNC' => node[id][:backend][:debug],
    'BEANSTALKD_URI' => "#{node[id][:beanstalkd][:listen][:address]}:#{node[id][:beanstalkd][:listen][:port]}",
    'BEANSTALKD_TUBE_NAMESPACE' => node[id][:beanstalkd][:tube_namespace],
    'REDIS_HOST' => node[id][:redis][:listen][:address],
    'REDIS_PORT' => node[id][:redis][:listen][:port],
    'REDIS_DB' => node[id][:redis][:db],
    'PG_HOST' => node[id][:postgres][:listen][:address],
    'PG_PORT' => node[id][:postgres][:listen][:port],
    'PG_USERNAME' => node[id][:postgres][:username],
    'PG_PASSWORD' => data_bag_item('postgres', node.chef_environment)['credentials'][node[id][:postgres][:username]],
    'PG_DATABASE' => node[id][:postgres][:dbname]
  )
  directory basedir
  serverurl 'AUTO'
  action :enable
end

supervisor_service "#{node[id][:supervisor][:namespace]}.scheduler" do
  command "#{rbenv_root}/shims/bundle exec ruby scheduler.rb"
  process_name 'scheduler'
  numprocs 1
  numprocs_start 0
  priority 300
  autostart false
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup false
  killasgroup false
  user node[id][:user]
  redirect_stderr false
  stdout_logfile ::File.join logs_basedir, 'scheduler-stdout.log'
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join logs_basedir, 'scheduler-stderr.log'
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  environment(
    'LOG_LEVEL' => node[id][:backend][:debug] ? 'DEBUG' : 'INFO',
    'STDOUT_SYNC' => node[id][:backend][:debug],
    'BEANSTALKD_URI' => "#{node[id][:beanstalkd][:listen][:address]}:#{node[id][:beanstalkd][:listen][:port]}",
    'BEANSTALKD_TUBE_NAMESPACE' => node[id][:beanstalkd][:tube_namespace],
    'REDIS_HOST' => node[id][:redis][:listen][:address],
    'REDIS_PORT' => node[id][:redis][:listen][:port],
    'REDIS_DB' => node[id][:redis][:db],
    'PG_HOST' => node[id][:postgres][:listen][:address],
    'PG_PORT' => node[id][:postgres][:listen][:port],
    'PG_USERNAME' => node[id][:postgres][:username],
    'PG_PASSWORD' => data_bag_item('postgres', node.chef_environment)['credentials'][node[id][:postgres][:username]],
    'PG_DATABASE' => node[id][:postgres][:dbname]
  )
  directory basedir
  serverurl 'AUTO'
  action :enable
end

team_logos_dir = ::File.join node[id][:basedir], 'team_logos'

supervisor_service "#{node[id][:supervisor][:namespace]}.app" do
  command "#{rbenv_root}/shims/bundle exec ruby backend.rb"
  process_name 'app-%(process_num)s'
  numprocs node[id][:backend][:app][:processes]
  numprocs_start 0
  priority 300
  autostart false
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup false
  killasgroup false
  user node[id][:user]
  redirect_stderr false
  stdout_logfile ::File.join logs_basedir, 'app-%(process_num)s-stdout.log'
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join logs_basedir, 'app-%(process_num)s-stderr.log'
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  environment(
    'TEAM_LOGOS_DIR' => team_logos_dir,
    'HOST' => '127.0.0.1',
    'PORT_RANGE_START' => node[id][:backend][:app][:port_range_start],
    'APP_INSTANCE' => '%(process_num)s',
    'LOG_LEVEL' => node[id][:backend][:debug] ? 'DEBUG' : 'INFO',
    'STDOUT_SYNC' => node[id][:backend][:debug],
    'RACK_ENV' => node.chef_environment,
    'BEANSTALKD_URI' => "#{node[id][:beanstalkd][:listen][:address]}:#{node[id][:beanstalkd][:listen][:port]}",
    'BEANSTALKD_TUBE_NAMESPACE' => node[id][:beanstalkd][:tube_namespace],
    'REDIS_HOST' => node[id][:redis][:listen][:address],
    'REDIS_PORT' => node[id][:redis][:listen][:port],
    'REDIS_DB' => node[id][:redis][:db],
    'PG_HOST' => node[id][:postgres][:listen][:address],
    'PG_PORT' => node[id][:postgres][:listen][:port],
    'PG_USERNAME' => node[id][:postgres][:username],
    'PG_PASSWORD' => data_bag_item('postgres', node.chef_environment)['credentials'][node[id][:postgres][:username]],
    'PG_DATABASE' => node[id][:postgres][:dbname]
  )
  directory basedir
  serverurl 'AUTO'
  action :enable
end
