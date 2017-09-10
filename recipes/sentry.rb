include_recipe 'libxml2::default'
include_recipe 'libxslt::default'
include_recipe 'libffi::default'

package 'libjpeg-dev' do
  action :install
end

id = 'themis-finals'
h = ::ChefCookbook::Instance::Helper.new(node)

basedir = ::File.join(node[id]['basedir'], 'sentry')

directory basedir do
  owner h.instance_user
  group h.instance_group
  mode 0755
  recursive true
  action :create
end

virtualenv_path = ::File.join(basedir, '.venv')

python_virtualenv virtualenv_path do
  user h.instance_user
  group h.instance_group
  python '2'
  action :create
end

requirements_file = ::File.join(basedir, 'requirements.txt')

cookbook_file requirements_file do
  source 'requirements.txt'
  owner h.instance_user
  group h.instance_group
  mode 0644
  action :create
end

pip_requirements requirements_file do
  user h.instance_user
  group h.instance_group
  virtualenv virtualenv_path
  action :install
end

postgres_root_username = 'postgres'

postgresql_connection_info = {
  host: node[id]['postgres']['host'],
  port: node[id]['postgres']['port'],
  username: postgres_root_username,
  password: data_bag_item('postgres', node.chef_environment)['credentials'][postgres_root_username]
}

postgresql_database node[id]['sentry']['postgres']['dbname'] do
  connection postgresql_connection_info
  action :create
end

postgresql_database_user node[id]['sentry']['postgres']['username'] do
  connection postgresql_connection_info
  database_name node[id]['sentry']['postgres']['dbname']
  password data_bag_item('postgres', node.chef_environment)['credentials'][node[id]['sentry']['postgres']['username']]
  privileges [:all]
  action [:create, :grant]
end

script_dir = ::File.join(node[id]['basedir'], 'script')
dump_db_script = ::File.join(script_dir, 'dump_sentry_db')

template dump_db_script do
  source 'dump_db.sh.erb'
  owner h.instance_user
  group h.instance_group
  mode 0775
  variables(
    pg_host: node[id]['postgres']['host'],
    pg_port: node[id]['postgres']['port'],
    pg_username: node[id]['sentry']['postgres']['username'],
    pg_password: data_bag_item('postgres', node.chef_environment)['credentials'][node[id]['sentry']['postgres']['username']],
    pg_dbname: node[id]['sentry']['postgres']['dbname']
  )
end

conf_file = ::File.join(basedir, 'sentry.conf.py')

template conf_file do
  source 'sentry.conf.py.erb'
  owner h.instance_user
  group h.instance_group
  variables(
    sentry_host: node[id]['sentry']['listen']['address'],
    sentry_port: node[id]['sentry']['listen']['port'],
    pg_host: node[id]['postgres']['host'],
    pg_port: node[id]['postgres']['port'],
    pg_name: node[id]['sentry']['postgres']['dbname'],
    pg_username: node[id]['sentry']['postgres']['username'],
    pg_password: data_bag_item('postgres', node.chef_environment)['credentials'][node[id]['sentry']['postgres']['username']],
    redis_host: node['latest-redis']['listen']['address'],
    redis_port: node['latest-redis']['listen']['port'],
    redis_db: node[id]['sentry']['redis']['db']
  )
  mode 0644
end

new_conf_file = ::File.join(basedir, 'config.yml')

template new_conf_file do
  source 'sentry.config.yml.erb'
  owner h.instance_user
  group h.instance_group
  variables(
    secret_key: data_bag_item('sentry', node.chef_environment)['secret_key'],
    url_prefix: "http://#{node[id]['fqdn']}:#{node[id]['sentry']['listen']['port']}",
    redis_host: node['latest-redis']['listen']['address'],
    redis_port: node['latest-redis']['listen']['port'],
    redis_db: node[id]['sentry']['redis']['db']
  )
end

python_execute 'Run Sentry database migration' do
  command '-m sentry upgrade --noinput'
  cwd basedir
  user h.instance_user
  group h.instance_group
  environment(
    'SENTRY_CONF' => basedir
  )
  action :run
end

bootstrap_script = ::File.join(basedir, 'bootstrap.py')

cookbook_file bootstrap_script do
  source 'sentry_bootstrap.py'
  owner h.instance_user
  group h.instance_group
  mode 0644
  action :create
end

python_execute 'Bootstrap Sentry' do
  command 'bootstrap.py'
  cwd basedir
  user h.instance_user
  group h.instance_group
  environment(
    'SENTRY_CONF' => basedir,
    'THEMIS_FINALS_SENTRY_ORGANIZATION' => node[id]['sentry']['config']['organization'],
    'THEMIS_FINALS_SENTRY_TEAMS' => node[id]['sentry']['config']['teams'].join(';'),
    'THEMIS_FINALS_SENTRY_PROJECTS' => node[id]['sentry']['config']['projects'].map { |x, y| "#{x}:#{y.join(',')}" }.join(';'),
    'THEMIS_FINALS_SENTRY_ADMINS' => data_bag_item('sentry', node.chef_environment)['admins'].map { |x, y| "#{x}:#{y}" }.join(';'),
    'THEMIS_FINALS_SENTRY_USERS' => data_bag_item('sentry', node.chef_environment)['users'].map { |x, y| "#{x}:#{y}" }.join(';')
  )
  action :run
end

namespace = "#{node['themis-finals']['supervisor_namespace']}.sentry"

supervisor_service "#{namespace}.web" do
  command "#{::File.join(virtualenv_path, 'bin', 'sentry')} run web"
  process_name 'web'
  numprocs 1
  numprocs_start 0
  priority 300
  autostart true
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup false
  killasgroup false
  user h.instance_user
  redirect_stderr false
  stdout_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.web-stdout.log")
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.web-stderr.log")
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  environment(
    'PATH' => "#{::File.join(virtualenv_path, 'bin')}:%(ENV_PATH)s",
    'SENTRY_CONF' => basedir
  )
  directory basedir
  serverurl 'AUTO'
  action :enable
end

supervisor_service "#{namespace}.celery_worker" do
  command "#{::File.join(virtualenv_path, 'bin', 'sentry')} celery worker"
  process_name 'celery_worker'
  numprocs 1
  numprocs_start 0
  priority 300
  autostart true
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup false
  killasgroup false
  user h.instance_user
  redirect_stderr false
  stdout_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.celery_worker-stdout.log")
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.celery_worker-stderr.log")
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  environment(
    'PATH' => "#{::File.join(virtualenv_path, 'bin')}:%(ENV_PATH)s",
    'SENTRY_CONF' => basedir
  )
  directory basedir
  serverurl 'AUTO'
  action :enable
end

supervisor_service "#{namespace}.celery_beat" do
  command "#{::File.join(virtualenv_path, 'bin', 'sentry')} celery beat"
  process_name 'celery_beat'
  numprocs 1
  numprocs_start 0
  priority 300
  autostart true
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup false
  killasgroup false
  user h.instance_user
  redirect_stderr false
  stdout_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.celery_beat-stdout.log")
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.celery_beat-stderr.log")
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  environment(
    'PATH' => "#{::File.join(virtualenv_path, 'bin')}:%(ENV_PATH)s",
    'SENTRY_CONF' => basedir
  )
  directory basedir
  serverurl 'AUTO'
  action :enable
end

supervisor_group namespace do
  programs [
    "#{namespace}.web",
    "#{namespace}.celery_worker",
    "#{namespace}.celery_beat"
  ]
  action [:enable, :start]
end

cleanup_script = ::File.join(script_dir, 'cleanup_sentry')

template cleanup_script do
  source 'cleanup_sentry.sh.erb'
  owner h.instance_user
  group h.instance_group
  mode 0775
  variables(
    virtualenv_path: virtualenv_path,
    environment: {
      'SENTRY_CONF' => basedir
    }
  )
end
