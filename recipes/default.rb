id = 'themis-finals'

include_recipe "#{id}::prerequisite_ntp"

include_recipe "#{id}::prerequisite_git"
include_recipe "#{id}::prerequisite_python"
include_recipe "#{id}::prerequisite_ruby"
include_recipe "#{id}::prerequisite_nodejs"

include_recipe "#{id}::prerequisite_nginx"
include_recipe "#{id}::prerequisite_redis"
include_recipe "#{id}::prerequisite_beanstalkd"
include_recipe "#{id}::prerequisite_postgres"

directory node[id][:basedir] do
  owner node[id][:user]
  group node[id][:group]
  mode 0755
  recursive true
  action :create
end

if node.chef_environment.start_with? 'development'
  ssh_data_bag_item = {}
  begin
    ssh_data_bag_item = data_bag_item('ssh', node.chef_environment)
  rescue
  end

  ssh_key_map = (ssh_data_bag_item.nil?) ? {} : ssh_data_bag_item.to_hash.fetch('keys', {})

  ssh_key_map.each do |key_type, key_contents|
    ssh_user_private_key key_type do
      key key_contents
      user node[id][:user]
    end
  end
end

rbenv_gem 'god' do
  ruby_version node[id][:ruby][:version]
end

god_basedir = ::File.join node[id][:basedir], 'god.d'

directory god_basedir do
  owner node[id][:user]
  group node[id][:group]
  mode 0755
  recursive true
  action :create
end

template "#{node[id][:basedir]}/god.conf" do
  source 'god.conf.erb'
  mode 0644
  variables(
    god_basedir: god_basedir,
  )
  action :create
end

logs_basedir = ::File.join node[id][:basedir], 'logs'

directory logs_basedir do
  owner node[id][:user]
  group node[id][:group]
  mode 0755
  recursive true
  action :create
end

checkers_basedir = ::File.join node[id][:basedir], 'checkers'

directory checkers_basedir do
  owner node[id][:user]
  group node[id][:group]
  mode 0755
  recursive true
  action :create
end

team_logos_dir = ::File.join node[id][:basedir], 'team_logos'

directory team_logos_dir do
  owner node[id][:user]
  group node[id][:group]
  mode 0755
  recursive true
  action :create
end

include_recipe "#{id}::backend"
include_recipe "#{id}::frontend"
include_recipe "#{id}::stream"

template "#{node[:nginx][:dir]}/sites-available/themis-finals.conf" do
  source 'nginx.conf.erb'
  mode 0644
  variables(
    logs_basedir: logs_basedir,
    frontend_basedir: ::File.join(node[id][:basedir], 'frontend'),
    backend_app_processes: node[id][:backend][:app][:processes],
    backend_app_port_range_start: node[id][:backend][:app][:port_range_start],
    stream_processes: node[id][:stream][:processes],
    stream_port_range_start: node[id][:stream][:port_range_start]
  )
  notifies :reload, 'service[nginx]', :delayed
  action :create
end

nginx_site 'themis-finals.conf'

include_recipe "#{id}::tools_monitoring"
