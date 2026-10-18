require "rails/generators"
require "active_record"

module AhoyDashboard
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def self.desc(description = nil)
        return super if description

        width = Installation::FEATURES.map { |feature| feature.name.length }.max
        features = Installation::FEATURES.map { |feature| "  #{feature.name.to_s.ljust(width)}  #{feature.label}" }

        <<~DESC
          Installs AhoyDashboard, or brings an existing install up to date. Safe to run again.

          Features for --only and --skip, comma separated (--only serp,alerts):
          #{features.join("\n")}

          The core tables are always installed.
        DESC
      end

      INITIALIZER = "config/initializers/ahoy_dashboard.rb".freeze

      DEFAULT_MOUNT = "/analytics-dashboard".freeze

      SAFE_MOUNT = %r{\A/[a-zA-Z0-9\-_/]*\z}

      SCOPE = "ahoy_dashboard".freeze

      FILENAME = /\A(?<version>\d+)_(?<name>[_a-z0-9]+?)(?:\.[_a-z0-9]+)?\.rb\z/

      LEGACY = {
        "create_ahoy_dashboard_core" => %w[
          create_ahoy_dashboard_goals create_ahoy_dashboard_properties create_ahoy_dashboard_funnels
          create_ahoy_dashboard_segments create_ahoy_dashboard_saved_queries create_ahoy_dashboard_page_groups
          create_ahoy_dashboard_annotations change_ahoy_dashboard_annotations_to_happened_at
          create_ahoy_dashboard_credentials create_ahoy_dashboard_job_runs create_ahoy_dashboard_job_run_entries
          create_ahoy_dashboard_settings add_applied_by_default_to_ahoy_dashboard_segments
          create_ahoy_dashboard_exclusions
        ],
        "create_ahoy_dashboard_search_console" => %w[
          create_ahoy_dashboard_google_accounts create_ahoy_dashboard_search_console_rows
          create_ahoy_dashboard_search_console_keywords add_device_and_country_to_ahoy_dashboard_search_console
          create_ahoy_dashboard_search_console_days
        ],
        "create_ahoy_dashboard_search_providers" => %w[
          create_ahoy_dashboard_serp_providers create_ahoy_dashboard_serp_spend_days
        ],
        "create_ahoy_dashboard_serp" => %w[
          create_ahoy_dashboard_serp_sites create_ahoy_dashboard_serp_keywords create_ahoy_dashboard_serp_runs
          create_ahoy_dashboard_serp_checks create_ahoy_dashboard_serp_results add_tags_to_ahoy_dashboard_serp_keywords
        ],
        "add_ahoy_dashboard_alert_check_foreign_keys" => %w[add_checks_to_ahoy_dashboard_alert_events],
        "create_ahoy_dashboard_assistant" => %w[
          create_ahoy_dashboard_chats create_ahoy_dashboard_assistant_providers
          add_views_to_ahoy_dashboard_chat_messages add_context_to_ahoy_dashboard_chats
          add_tuning_to_ahoy_dashboard_assistant_providers
        ],
        "create_ahoy_dashboard_ai_visibility_tables" => %w[
          create_ahoy_dashboard_ai_visibility add_models_to_ahoy_dashboard_ai_visibility
        ],
        "create_ahoy_dashboard_alert_tables" => %w[
          create_ahoy_dashboard_alerts add_checks_to_ahoy_dashboard_alert_events
          create_ahoy_dashboard_alert_digests add_readings_to_ahoy_dashboard_alert_events
          add_floor_to_ahoy_dashboard_alert_rules
        ]
      }.freeze

      class_option :at, type: :string, default: DEFAULT_MOUNT,
                        desc: "Where to mount the engine"
      class_option :only, type: :string, default: "", banner: "serp,alerts",
                          desc: "Install only these features, comma separated, plus the core tables everything needs"
      class_option :skip, type: :string, default: "", banner: "serp,alerts",
                          desc: "Install every feature except these, comma separated"
      class_option :skip_routes, type: :boolean, default: false,
                                 desc: "Leave config/routes.rb alone"
      class_option :skip_migrations, type: :boolean, default: false,
                                     desc: "Do not copy the migrations"

      def initialize(args = [], local_options = {}, config = {})
        super
        @stray = local_options.is_a?(Array) ? Thor::Options.new(self.class.class_options).tap { |parser| parser.parse(local_options) }.remaining : []
      end

      def self.names(value)
        value.to_s.split(",").map(&:strip).reject(&:empty?)
      end

      def check_options
        if @stray.any?
          flag = skip.any? ? "--skip" : "--only"
          raise Thor::Error, "separate features with commas, not spaces: #{flag} #{[ *only, *skip, *@stray ].join(",")}"
        end

        mount_at unless options[:skip_routes]
        raise Thor::Error, "pass --only or --skip, not both" if only.any? && skip.any?

        unknown = (only + skip).map(&:to_sym) - Installation.names
        return if unknown.empty?

        raise Thor::Error, "no feature named #{unknown.join(", ")}. features: #{Installation.names.join(", ")}"
      end

      def create_initializer
        if File.exist?(File.join(destination_root, INITIALIZER))
          say_status :exist, INITIALIZER, :blue
        else
          template "initializer.rb", INITIALIZER
        end
      end

      def mount_engine
        return if options[:skip_routes]

        unless routes_file.exist?
          say_status :skip, "no config/routes.rb, mount it yourself", :yellow
          return
        end

        if routes_file.read.include?("AhoyDashboard::Engine")
          say_status :identical, "config/routes.rb already mounts AhoyDashboard::Engine", :blue
          return
        end

        route %(mount AhoyDashboard::Engine, at: "#{mount_at}")
      end

      def copy_migrations
        return if options[:skip_migrations]

        candidates = wanted_groups.flat_map { |group| Installation::GROUPS.fetch(group).map { |name| [ group, name ] } }
        check_legacy!(candidates.map(&:last))
        sources = candidates.reject { |_group, name| migration_here?(name) }
        @copied = sources.size

        if sources.empty?
          say_status :identical, "every migration for core#{wanted_features.map { |name| ", #{name}" }.join} is already here", :blue
          return
        end

        FileUtils.mkdir_p(migrations_path)
        version = last_version

        sources.each do |group, name|
          version = ActiveRecord::Migration.next_migration_number(version + 1).to_i
          target = File.join(migrations_path, "#{version}_#{name}.#{SCOPE}.rb")
          File.write(target, "# This migration comes from #{SCOPE}\n#{Installation.migrations_root.join(group, "#{name}.rb").read}")
          say_status :create, relative(target)
        end
      end

      def report
        say ""
        unless options[:skip_migrations]
          @existing = nil
          installed = Installation.names.select { |name| installed_feature?(name) }
          left_out = Installation.names - installed

          say "installed: core#{installed.map { |name| ", #{name}" }.join}"
          say "not installed: #{left_out.join(", ")}. add one with bin/rails generate ahoy_dashboard:install --only <feature>" if left_out.any?
        end
        say "next: bin/rails db:migrate" if @copied.to_i.positive?
      end

      private

      def only
        self.class.names(options[:only])
      end

      def skip
        self.class.names(options[:skip])
      end

      def wanted_features
        @wanted_features ||=
          if only.any? then Installation.names & only.map(&:to_sym)
          elsif skip.any? then Installation.names - skip.map(&:to_sym)
          elsif !installed_before? then Installation.names
          else Installation.names.select { |name| installed_feature?(name) }
          end
      end

      def wanted_groups
        Installation.groups_for(wanted_features)
      end

      def installed_feature?(name)
        Installation.fetch(name).groups.all? do |group|
          Installation::GROUPS.fetch(group).any? { |migration| migration_here?(migration) }
        end
      end

      def installed_before?
        Installation::GROUPS.fetch(Installation::CORE).any? { |migration| migration_here?(migration) }
      end

      def migration_here?(name)
        existing.include?(name) || LEGACY.fetch(name, []).any? { |legacy| existing.include?(legacy) }
      end

      def replaced?(name)
        !existing.include?(name) && LEGACY.fetch(name, []).any? { |old| existing.include?(old) }
      end

      def check_legacy!(names)
        missing = names.select { |name| replaced?(name) }
          .flat_map { |name| LEGACY.fetch(name).reject { |old| ran?(old) } }
        return if missing.empty?

        unchecked = database ? "" : " (the database could not be reached, so this is going by db/migrate alone)"
        raise Thor::Error, "this app ran an older ahoy_dashboard but is missing some of its migrations: " \
                           "#{missing.join(", ")}. copy those from the version you had, run them, then try again#{unchecked}"
      end

      def ran?(old)
        existing.include?(old) || (database && Installation::LegacyMigration.fetch(old).applied?(database))
      end

      def database
        return @database if defined?(@database)

        @database = AhoyDashboard::Record.connection.tap(&:verify!)
      rescue ActiveRecord::ActiveRecordError
        @database = nil
      end

      def host_migrations
        Pathname(migrations_path).glob("**/*.rb").map { |file| File.basename(file) }
      end

      def existing
        @existing ||= host_migrations.map { |file| file[FILENAME, :name] }.select { |value| value }.to_set
      end

      def last_version
        host_migrations.map { |file| file[FILENAME, :version]&.to_i }.select { |value| value }.max.to_i
      end

      def migrations_path
        File.join(destination_root, "db/migrate")
      end

      def relative(path)
        Pathname(path).relative_path_from(Pathname(destination_root)).to_s
      end

      def mount_at
        @mount_at ||= begin
          wanted = options[:at].to_s
          wanted = "/#{wanted}" unless wanted.start_with?("/")
          wanted = wanted.chomp("/") if wanted.length > 1

          unless wanted.match?(SAFE_MOUNT)
            raise Thor::Error, "--at #{options[:at].inspect} is not a route path"
          end

          wanted
        end
      end

      def routes_file
        Pathname(destination_root).join("config/routes.rb")
      end
    end
  end
end
