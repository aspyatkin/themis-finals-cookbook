id = 'themis-finals'
instance = ::ChefCookbook::Instance::Helper.new(node)
h = ::ChefCookbook::Themis::Finals::Helper.new(node)

url_repository = "https://github.com/#{node[id]['frontend']['github_repository']}"

directory h.frontend_dir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

if node.chef_environment.start_with?('development')
  ssh_private_key instance.user
  ssh_known_hosts_entry 'github.com'
  url_repository = "git@github.com:#{node[id]['frontend']['github_repository']}.git"
end

git2 h.frontend_dir do
  url url_repository
  branch node[id]['frontend']['revision']
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
    git_config "git-config #{key} at #{h.frontend_dir}" do
      key key
      value value
      scope 'local'
      path h.frontend_dir
      user instance.user
      action :set
    end
  end
end

yarn_install h.frontend_dir do
  user instance.user
  action :run
end

customize_cookbook = node[id].fetch('customize_cookbook', nil)
frontend_customize_module = node[id].fetch('frontend_customize_module', nil)
if customize_cookbook.nil? || frontend_customize_module.nil?
  execute "Copy customization file at #{h.frontend_dir}" do
    command 'cp customize.example.js customize.js'
    cwd h.frontend_dir
    user instance.user
    group instance.group
    not_if "test -e #{h.frontend_dir}/customize.js"
  end
else
  cookbook_file ::File.join(h.frontend_dir, 'customize.js') do
    cookbook customize_cookbook
    source frontend_customize_module
    owner instance.user
    group instance.group
    mode 0644
    action :create
  end
end

unless customize_cookbook.nil?
  node[id].fetch('frontend_extra_files', {}).each do |name_, path_path|
    full_path = ::File.join(h.frontend_dir, path_path)
    cookbook_file full_path do
      cookbook customize_cookbook
      source name_
      owner instance.user
      group instance.group
      mode 0644
      action :create
    end
  end
end

yarn_run "Build scripts at #{h.frontend_dir}" do
  script 'build'
  user instance.user
  dir h.frontend_dir
  production node.chef_environment.start_with?('production')
  action :run
end
