module ChefCookbook
  module Themis
    module Finals
      class Helper
        def initialize(node)
          @id = 'themis-finals'
          @node = node
          @secret = ::ChefCookbook::Secret::Helper.new(node)
        end

        def postgres_host
          host, _ = resolve_postgres
          host
        end

        def postgres_port
          _, port = resolve_postgres
          port
        end

        def redis_host
          host, _ = resolve_redis
          host
        end

        def redis_port
          _, port = resolve_redis
          port
        end

        def env
          {
            'REDIS_HOST' => redis_host,
            'REDIS_PORT' => redis_port,
            'REDIS_PASSWORD' => @secret.get('redis:password', required: false, default: nil),

            'PG_HOST' => postgres_host,
            'PG_PORT' => postgres_port,
            'PG_USERNAME' => @node[@id]['postgres']['username'],
            'PG_PASSWORD' => @secret.get("postgres:password:#{@node[@id]['postgres']['username']}"),
            'PG_DATABASE' => @node[@id]['postgres']['dbname'],

            'THEMIS_FINALS_STREAM_REDIS_DB' => @node[@id]['stream']['redis_db'],
            'THEMIS_FINALS_QUEUE_REDIS_DB' => @node[@id]['backend']['queue']['redis_db'],
            'THEMIS_FINALS_STREAM_REDIS_CHANNEL_NAMESPACE' => @node[@id]['stream']['redis_channel_namespace'],

            'THEMIS_FINALS_MASTER_FQDN' => @node[@id]['fqdn'],

            'THEMIS_FINALS_TEAM_LOGO_DIR' => team_logo_dir,

            'THEMIS_FINALS_AUTH_CHECKER_USERNAME' => @secret.get('themis-finals:auth:checker:username'),
            'THEMIS_FINALS_AUTH_CHECKER_PASSWORD' => @secret.get('themis-finals:auth:checker:password'),

            'THEMIS_FINALS_FLAG_GENERATOR_SECRET' => @secret.get('themis-finals:flag_generator_secret'),
            'THEMIS_FINALS_FLAG_SIGN_KEY_PRIVATE' => @secret.get('themis-finals:sign_key:private').gsub("\n", "\\n"),
            'THEMIS_FINALS_FLAG_SIGN_KEY_PUBLIC' => @secret.get('themis-finals:sign_key:public').gsub("\n", "\\n"),
            'THEMIS_FINALS_FLAG_WRAP_PREFIX' => @node[@id]['flag_wrap']['prefix'],
            'THEMIS_FINALS_FLAG_WRAP_SUFFIX' => @node[@id]['flag_wrap']['suffix']
          }
        end

        def backend_dir
          ::File.join(@node[@id]['basedir'], 'backend')
        end

        def script_dir
          ::File.join(@node[@id]['basedir'], 'script')
        end

        def media_dir
          ::File.join(@node[@id]['basedir'], 'media')
        end

        def team_logo_dir
          ::File.join(@node[@id]['basedir'], 'team_logo')
        end

        def stream_dir
          ::File.join(@node[@id]['basedir'], 'stream')
        end

        def visualization_dir
          ::File.join(@node[@id]['basedir'], 'visualization')
        end

        def frontend_dir
          ::File.join(@node[@id]['basedir'], 'frontend')
        end

        def domain_dir
          ::File.join(@node[@id]['basedir'], 'domain')
        end

        private
        def resolve_postgres
          ::ChefCookbook::LocalDNS::resolve_service('postgres', 'tcp', @node['themis']['finals']['ns'])
        end

        def resolve_redis
          ::ChefCookbook::LocalDNS::resolve_service('redis', 'tcp', @node['themis']['finals']['ns'])
        end
      end
    end
  end
end
