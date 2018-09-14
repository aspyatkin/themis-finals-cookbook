id = 'themis-finals'

secret = ::ChefCookbook::Secret::Helper.new(node)
h = ::ChefCookbook::Themis::Finals::Helper.new(node)

include_recipe 'database::postgresql'

postgresql_connection_info = {}

ruby_block 'configure postgres' do
  block do
    postgresql_connection_info = {
      host: h.postgres_host,
      port: h.postgres_port,
      username: 'postgres',
      password: secret.get('postgres:password:postgres')
    }
  end
  action :run
end

postgresql_database node[id]['postgres']['dbname'] do
  connection lazy { postgresql_connection_info }
  action :create
end

postgresql_database_user node[id]['postgres']['username'] do
  connection lazy { postgresql_connection_info }
  database_name node[id]['postgres']['dbname']
  password secret.get("postgres:password:#{node[id]['postgres']['username']}")
  privileges [:all]
  action [:create, :grant]
end
