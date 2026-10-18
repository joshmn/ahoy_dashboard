require "rails_helper"
require "generators/ahoy_dashboard/install/install_generator"

RSpec.describe AhoyDashboard::Generators::InstallGenerator do
  around do |example|
    Dir.mktmpdir do |dir|
      @destination = dir
      example.run
    end
  end

  def run_generator(*args)
    run_install_generator(@destination, *args)
  end

  it "writes the initializer and leaves explaining it to the file" do
    output = run_generator("--skip-migrations")
    initializer = File.read(File.join(@destination, "config/initializers/ahoy_dashboard.rb"))

    expect(initializer).to include("config.authorize = ->(controller) { controller.current_user&.admin? }")
    expect(output).to include("create  config/initializers/ahoy_dashboard.rb")
    expect(output).not_to include("authorize")
  end

  it "writes an initializer that boots against the configuration as it is now" do
    run_generator("--skip-migrations")
    config = AhoyDashboard::Configuration.new
    allow(AhoyDashboard).to receive(:configure).and_yield(config)

    expect { load File.join(@destination, "config/initializers/ahoy_dashboard.rb") }.not_to raise_error
    expect(config.authorize).to respond_to(:call)
  end

  describe "migrations" do
    let(:engine_migrations) { AhoyDashboard::Installation.migrations_root }

    def copied
      Dir[File.join(@destination, "db/migrate/*.rb")].map { |file| File.basename(file)[/\A\d+_(.+)\.ahoy_dashboard\.rb\z/, 1] }.sort
    end

    def names_in(*groups)
      groups.flat_map { |group| engine_migrations.join(group).glob("*.rb") }.map { |file| file.basename(".rb").to_s.sub(/\A\d+_/, "") }.sort
    end

    def install_legacy(names)
      FileUtils.mkdir_p(File.join(@destination, "db/migrate"))
      names.each_with_index do |name, index|
        File.write(File.join(@destination, "db/migrate/2026080100#{format("%04d", index)}_#{name}.ahoy_dashboard.rb"), "")
      end
    end

    it "copies every feature on a fresh install, in order, with a version on each" do
      run_generator

      expect(copied).to eq(names_in(*engine_migrations.children.select(&:directory?).map { |dir| dir.basename.to_s }))

      files = Dir[File.join(@destination, "db/migrate/*.rb")].sort
      expect(files.map { |file| File.basename(file)[/\A\d+_(.+)\.ahoy_dashboard\.rb\z/, 1] })
        .to eq(AhoyDashboard::Installation::GROUPS.values.flatten)
      expect(File.read(files.first)).to start_with("# This migration comes from ahoy_dashboard\n")
    end

    it "numbers its copies after the newest migration already in the app" do
      FileUtils.mkdir_p(File.join(@destination, "db/migrate"))
      File.write(File.join(@destination, "db/migrate/99990101000000_create_widgets.rb"), "")

      run_generator("--only", "reports")

      versions = Dir[File.join(@destination, "db/migrate/*.ahoy_dashboard.rb")].map { |file| File.basename(file).to_i }
      expect(versions.min).to be > 99990101000000
    end

    it "copies core and only the named features, with the tables they share" do
      output = run_generator("--only", "keywords,alerts")

      expect(copied).to eq(names_in("core", "search_providers", "keywords", "alerts"))
      expect(output).to include("installed: core, keywords, alerts")
      expect(output).to include("not installed: search_console, serp, backlinks, places, assistant, ai_visibility, reports")
    end

    it "tells you to use commas when names are separated by spaces" do
      expect(run_generator("--only", "serp", "reports")).to include("separate features with commas, not spaces: --only serp,reports")
      expect(run_generator("--skip", "serp", "reports")).to include("--skip serp,reports")
      expect(copied).to be_empty
    end

    it "lists every feature in its help" do
      lines = AhoyDashboard::Installation::FEATURES.map { |feature| match(/^\s+#{feature.name}\s+#{feature.label}$/) }

      expect { described_class.help(Thor::Base.shell.new) }.to output(lines.reduce(include("comma separated"), :and)).to_stdout
    end

    it "copies every feature but the skipped ones" do
      run_generator("--skip", "serp,assistant")

      expect(copied).not_to include(*names_in("serp", "assistant"))
      expect(copied).to include(*names_in("core", "search_providers", "keywords", "backlinks", "alerts"))
    end

    it "keeps to what is installed on a later run, and adds a feature when asked" do
      run_generator("--only", "alerts")
      before = copied

      run_generator
      expect(copied).to eq(before)

      run_generator("--only", "serp")
      expect(copied).to eq(names_in("core", "alerts", "search_providers", "serp"))
    end

    it "copies nothing into an app that already ran the migrations these replace" do
      legacy = described_class::LEGACY.values.flatten.uniq + names_in("core", "keywords", "backlinks", "places", "reports") +
               %w[remove_ahoy_dashboard_search_console_rows_date_index add_ahoy_dashboard_serp_lookup_indexes
                  add_ahoy_dashboard_chat_message_reasoning]
      install_legacy(legacy)
      count = copied.size

      output = run_generator

      expect(copied.size).to eq(count)
      expect(output).to include("installed: core, search_console, serp, keywords, backlinks, places, assistant, ai_visibility, alerts, reports")
    end

    it "brings an app that ran the migrations these replace the indexes added since" do
      install_legacy(described_class::LEGACY.values.flatten.uniq + names_in("core", "keywords", "backlinks", "places", "reports"))
      before = copied

      run_generator

      expect(copied - before).to contain_exactly("remove_ahoy_dashboard_search_console_rows_date_index",
                                                 "add_ahoy_dashboard_serp_lookup_indexes",
                                                 "add_ahoy_dashboard_chat_message_reasoning")
    end

    it "refuses an app with only some of the migrations one of these replaces, when the database lacks it too" do
      install_legacy(described_class::LEGACY.values.flatten.uniq - %w[add_floor_to_ahoy_dashboard_alert_rules] +
                     names_in("core", "keywords", "backlinks", "places", "reports"))
      count = copied.size
      connection = AhoyDashboard::Record.connection
      allow(connection).to receive(:column_exists?).and_call_original
      allow(connection).to receive(:column_exists?).with("ahoy_dashboard_alert_rules", "floor").and_return(false)

      output = run_generator

      expect(output).to include("is missing some of its migrations: add_floor_to_ahoy_dashboard_alert_rules. copy those")
      expect(output).not_to include("could not be reached")
      expect(output).not_to include("identical")
      expect(copied.size).to eq(count)
    end

    it "goes ahead when the files are gone but the database has what they made, as in a renamed app" do
      gone = %w[
        create_ahoy_dashboard_goals create_ahoy_dashboard_properties create_ahoy_dashboard_funnels
        create_ahoy_dashboard_segments create_ahoy_dashboard_saved_queries create_ahoy_dashboard_page_groups
        create_ahoy_dashboard_annotations change_ahoy_dashboard_annotations_to_happened_at
        create_ahoy_dashboard_google_accounts create_ahoy_dashboard_search_console_rows
        create_ahoy_dashboard_search_console_keywords create_ahoy_dashboard_serp_providers create_ahoy_dashboard_serp_sites
        create_ahoy_dashboard_serp_keywords create_ahoy_dashboard_serp_runs create_ahoy_dashboard_serp_checks
        create_ahoy_dashboard_serp_results create_ahoy_dashboard_chats create_ahoy_dashboard_assistant_providers
        add_views_to_ahoy_dashboard_chat_messages add_context_to_ahoy_dashboard_chats
      ]
      install_legacy(described_class::LEGACY.values.flatten.uniq - gone +
                     names_in("core", "keywords", "backlinks", "places", "reports") - %w[create_ahoy_dashboard_core])
      before = copied

      output = run_generator

      expect(output).not_to include("missing some of its migrations")
      expect(copied - before).to contain_exactly("remove_ahoy_dashboard_search_console_rows_date_index",
                                                 "add_ahoy_dashboard_serp_lookup_indexes",
                                                 "add_ahoy_dashboard_chat_message_reasoning")
    end

    it "goes by db/migrate alone and says so when the database cannot be reached" do
      install_legacy(described_class::LEGACY.values.flatten.uniq - %w[create_ahoy_dashboard_goals] +
                     names_in("core", "keywords", "backlinks", "places", "reports") - %w[create_ahoy_dashboard_core])
      count = copied.size
      allow(AhoyDashboard::Record).to receive(:connection).and_raise(ActiveRecord::ConnectionNotEstablished)

      output = run_generator

      expect(output).to include("is missing some of its migrations: create_ahoy_dashboard_goals. copy those")
      expect(output).to include("the database could not be reached, so this is going by db/migrate alone")
      expect(copied.size).to eq(count)
    end

    it "knows what every migration these replace made, and finds all of it in a full install" do
      names = described_class::LEGACY.values.flatten.uniq
      connection = AhoyDashboard::Record.connection

      expect(AhoyDashboard::Installation::LegacyMigration::ALL.map(&:name)).to match_array(names)
      aggregate_failures do
        names.each do |name|
          expect(AhoyDashboard::Installation::LegacyMigration.fetch(name).applied?(connection)).to be(true), "#{name} not found"
        end
      end
    end

    it "refuses a feature it does not know and both flags at once" do
      expect(run_generator("--only", "rankings")).to include("no feature named rankings")
      expect(run_generator("--only", "serp", "--skip", "alerts")).to include("pass --only or --skip, not both")
      expect(copied).to be_empty
    end

    it "writes nothing when a feature name is wrong" do
      run_generator("--only", "nope")

      expect(File).not_to exist(File.join(@destination, "config/initializers/ahoy_dashboard.rb"))
      expect(copied).to be_empty
    end

    it "keeps an initializer that is already there when it runs again" do
      run_generator
      initializer = File.join(@destination, "config/initializers/ahoy_dashboard.rb")
      File.write(initializer, "# mine")

      output = run_generator("--only", "serp")

      expect(File.read(initializer)).to eq("# mine")
      expect(output).to include("exist  config/initializers/ahoy_dashboard.rb")
    end

    describe "the feature list" do
      def created_tables(groups)
        groups.flat_map { |group| engine_migrations.join(group).glob("*.rb") }
          .flat_map { |file| file.read.scan(/create_table :(\w+)/).flatten }.sort
      end

      it "names exactly the tables each feature's migrations create" do
        AhoyDashboard::Installation::FEATURES.each do |feature|
          expect(feature.tables.sort).to eq(created_tables(feature.groups)), feature.name.to_s
        end
      end

      it "accounts for every migration directory and leaves no migration outside one" do
        groups = AhoyDashboard::Installation::FEATURES.flat_map(&:groups) + [ AhoyDashboard::Installation::CORE ]

        expect(engine_migrations.children.select(&:directory?).map { |dir| dir.basename.to_s }).to match_array(groups.uniq)
        expect(AhoyDashboard::Installation::GROUPS.keys).to match_array(groups.uniq)
        expect(engine_migrations.glob("*.rb")).to be_empty
      end

      it "orders every migration file and nothing else" do
        AhoyDashboard::Installation::GROUPS.each do |group, names|
          expect(engine_migrations.join(group).glob("*.rb").map { |file| file.basename(".rb").to_s }).to match_array(names), group
        end
      end

      it "keeps version numbers out of the engine's file names" do
        expect(engine_migrations.glob("**/*.rb").map { |file| file.basename.to_s }.grep(/\A\d/)).to be_empty
      end

      it "is the list that can be switched on, less site icons, which need no tables" do
        expect(AhoyDashboard::Installation.names).to match_array(AhoyDashboard::Features.names - [ :favicons ])
      end
    end
  end
end
