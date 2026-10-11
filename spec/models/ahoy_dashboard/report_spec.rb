require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::Report do
  it "lays the cards out in one order" do
    expect(described_class.card_order).to eq(%w[sources pages locations devices behaviours])
  end

  it "registers a report for every card" do
    expect(described_class::ALL.map(&:key)).to match_array(described_class.card_order)
  end

  it "raises for a report nobody registered" do
    expect { described_class.find("vibes") }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "titles every card" do
    expect(described_class.find("sources").title).to eq("Top sources")
    expect(described_class.find("pages").title).to eq("Top pages")
    expect(described_class.find("locations").title).to eq("Locations")
    expect(described_class.find("devices").title).to eq("Devices")
    expect(described_class.find("behaviours").title).to eq("Behaviours")
  end

  describe "every tab" do
    it "points at a dimension that resolves" do
      described_class::ALL.each do |report|
        report.tabs.each do |tab|
          expect { tab.dimension }.not_to raise_error,
            "#{report.key}/#{tab.key} points at #{tab.resolved_dimension_key}, which is not a dimension"
        end
      end
    end

    it "asks for metrics that resolve" do
      described_class::ALL.each do |report|
        report.tabs.each do |tab|
          (tab.metrics + tab.detail_metrics).each do |key|
            next if key == "conversion_rate" || key == "events"

            expect { AhoyDashboard::Metric.find(key) }.not_to raise_error,
              "#{report.key}/#{tab.key} asks for the metric #{key}"
          end
        end
      end
    end

    it "carries a label and a column heading" do
      described_class::ALL.each do |report|
        report.tabs.each do |tab|
          expect(tab.label).to be_present, "#{report.key}/#{tab.key} has no label"
          expect(tab.label_column).to be_present, "#{report.key}/#{tab.key} has no label column"
        end
      end
    end
  end

  describe "every breakdown" do
    def breakdowns
      described_class::ALL.flat_map { |report| report.tabs.map { |tab| [ report, tab ] } }
        .flat_map { |report, tab| tab.breakdown_options.map { |option| [ report, tab, option ] } }
    end

    it "points at a dimension that resolves" do
      breakdowns.each do |report, tab, option|
        expect { AhoyDashboard::Dimension.find(option.dimension_key) }.not_to raise_error,
          "#{report.key}/#{tab.key}/#{option.key} points at #{option.dimension_key}"
      end
    end

    it "asks for metrics that resolve" do
      breakdowns.each do |report, tab, option|
        Array(option.detail_metrics).each do |key|
          expect { AhoyDashboard::Metric.find(key) }.not_to raise_error,
            "#{report.key}/#{tab.key}/#{option.key} asks for the metric #{key}"
        end
      end
    end

    it "carries a label and a column heading" do
      breakdowns.each do |report, tab, option|
        expect(option.label).to be_present, "#{report.key}/#{tab.key}/#{option.key} has no label"
        expect(option.label_column).to be_present,
          "#{report.key}/#{tab.key}/#{option.key} has no column heading"
      end
    end

    it "names each option once inside its own tab" do
      described_class::ALL.each do |report|
        report.tabs.each do |tab|
          keys = tab.breakdown_options.map(&:key)

          expect(keys).to eq(keys.uniq), "#{report.key}/#{tab.key} registers a key twice"
        end
      end
    end

    # The first option is what the card opens on, so a first option pointing
    # anywhere else means the card silently grouped by something nobody picked.
    it "opens on the tab's own dimension" do
      described_class::ALL.each do |report|
        report.tabs.each do |tab|
          next if tab.breakdown_options.empty?

          expect(tab.breakdown_options.first.dimension_key).to eq(tab.resolved_dimension_key),
            "#{report.key}/#{tab.key} opens on #{tab.breakdown_options.first.dimension_key}"
        end
      end
    end

    it "offers a path, the grouped paths and a controller on top pages" do
      tab = described_class.find("pages").tab("pages")

      expect(tab.breakdown_options.map(&:key)).to eq(%w[path grouped controller])
      expect(tab.breakdown_options.map(&:dimension_key)).to eq(%w[page page_group controller])
    end

    it "offers a path, a full url and a hostname on entry pages" do
      tab = described_class.find("pages").tab("entry_pages")

      expect(tab.breakdown_options.map(&:key)).to eq(%w[path url host])
      expect(tab.breakdown_options.map(&:dimension_key)).to eq(%w[entry_page entry_url entry_host])
    end

    # A page view records request.path and no host, so there is no full url on
    # the event to offer. Exit pages read a path off a derived table, same story.
    it "offers nothing on a tab whose data cannot answer a second question" do
      expect(described_class.find("pages").tab("exit_pages").breakdown_options).to be_empty
      expect(described_class.find("sources").tabs.flat_map(&:breakdown_options)).to be_empty
      expect(described_class.find("behaviours").tabs.flat_map(&:breakdown_options)).to be_empty
    end
  end

  describe "#resolve" do
    let(:pages) { described_class.find("pages").tab("pages") }
    let(:entry) { described_class.find("pages").tab("entry_pages") }
    let(:properties) { described_class.find("behaviours").tab("properties") }

    it "groups by the breakdown somebody asked for, and heads the column with it" do
      resolved = pages.resolve(breakdown: "controller")

      expect(resolved.resolved_dimension_key).to eq("controller")
      expect(resolved.label_column).to eq("Rails controller")
      expect(resolved.detail_metrics).to eq(%w[visitors pageviews bounce_rate])
    end

    it "keeps the tab's own key, so the tab stays the active one" do
      expect(pages.resolve(breakdown: "controller").key).to eq("pages")
      expect(pages.resolve(breakdown: "controller").label).to eq("Top pages")
    end

    it "keeps the tab's own metrics where the breakdown names none" do
      expect(entry.resolve(breakdown: "url").detail_metrics).to eq(entry.detail_metrics)
    end

    it "opens on the first option when nothing is asked for" do
      expect(entry.resolve.resolved_dimension_key).to eq("entry_page")
      expect(entry.resolve(breakdown: nil).label_column).to eq("Page url")
    end

    [ "", "  ", "banana", "url", "path; drop table ahoy_events", [ "url" ], { a: "b" } ].each do |value|
      it "falls back to the default for the breakdown value #{value.inspect}" do
        expect(pages.resolve(breakdown: value).resolved_dimension_key).to eq("page")
      end
    end

    # A breakdown belongs to one card. Another card's value reaching this one is
    # a hand-edited URL, and the answer is the tab as registered.
    it "ignores a breakdown on a tab that offers none" do
      exits = described_class.find("pages").tab("exit_pages")

      expect(exits.resolve(breakdown: "url")).to eq(exits)
      expect(described_class.find("sources").tab("channels").resolve(breakdown: "host").resolved_dimension_key)
        .to eq("channel")
    end

    it "groups by the property somebody asked for" do
      expect(properties.resolve(property: "results").resolved_dimension_key).to eq("prop:results")
      expect(properties.resolve(property: "results").property_tab?).to be(true)
    end

    it "groups by a key spelled any way an app can send it" do
      [ "facilityId", "plan-tier", "page.section", "plan name" ].each do |name|
        expect(properties.resolve(property: name).resolved_dimension_key).to eq("prop:#{name}")
      end
    end

    [ "", "  ", "line\nbreak", "a" * 256, [ "results" ], { "key" => "results" } ].each do |value|
      it "falls back to the allowlist's own key for the property value #{value.inspect}" do
        AhoyDashboard::Property.create!(key: "facility_id")

        expect(properties.resolve(property: value).resolved_dimension_key).to eq("prop:facility_id")
      end
    end

    it "ignores a property on a tab that is not the properties tab" do
      expect(pages.resolve(property: "facility_id").resolved_dimension_key).to eq("page")
    end
  end

  describe "#tab" do
    it "finds a tab by key" do
      expect(described_class.find("pages").tab("entry_pages").dimension_key).to eq("entry_page")
    end

    it "falls back to the default for a tab nobody registered" do
      report = described_class.find("pages")

      expect(report.tab("nope")).to eq(report.default_tab)
      expect(report.tab(nil)).to eq(report.default_tab)
    end

    it "defaults to a tab it actually has" do
      described_class::ALL.each do |report|
        expect(report.tabs).to include(report.default_tab),
          "#{report.key} defaults to a tab that is not one of its own"
      end
    end
  end

  describe ".register" do
    def tab(key: "ip", label: "IP", dimension_key: "country", metrics: %w[visits],
            detail_metrics: %w[visits visitors], label_column: "Widget", breakdowns: [])
      described_class::Tab.new(key: key, label: label, dimension_key: dimension_key,
                               metrics: metrics, detail_metrics: detail_metrics,
                               label_column: label_column, breakdowns: breakdowns)
    end

    def register(**overrides)
      described_class.register(**{ key: "widgets", title: "Widgets", tabs: [ tab ] }.merge(overrides))
    end

    it "adds a card nobody wrote to the dashboard" do
      register

      expect(described_class.find("widgets").title).to eq("Widgets")
      expect(described_class.all.map(&:key)).to include("widgets")
      expect(described_class.cards.map(&:key)).to include("widgets")
      expect(described_class.find_by_key("widgets")).to eq(described_class.find("widgets"))
    end

    it "lays a registered card out after every built-in one" do
      register

      keys = described_class.cards.map(&:key)

      expect(keys.first(described_class.card_order.size)).to eq(described_class.card_order)
      expect(keys.last).to eq("widgets")
    end

    it "leaves the built-in registry alone" do
      register

      expect(described_class::ALL.map(&:key)).to match_array(described_class.card_order)
      expect(described_class.card_order).not_to include("widgets")
    end

    it "overwrites its own entry instead of raising, since to_prepare re-runs it on every reload" do
      register
      register(title: "Gadgets")

      expect(described_class.find("widgets").title).to eq("Gadgets")
      expect(described_class.cards.count { |report| report.key == "widgets" }).to eq(1)
    end

    it "opens on its first tab" do
      report = register(tabs: [ tab(key: "ip"), tab(key: "asn", dimension_key: "browser") ])

      expect(report.default_tab.key).to eq("ip")
    end

    it "opens on the tab it was told to" do
      report = register(default_tab: "asn",
                        tabs: [ tab(key: "ip"), tab(key: "asn", dimension_key: "browser") ])

      expect(report.default_tab.key).to eq("asn")
    end

    it "is half width unless it asks for the whole row" do
      expect(register).not_to be_wide
      expect(register(wide: true)).to be_wide
    end

    it "refuses to alias a built-in key" do
      expect { register(key: "pages") }.to raise_error(ArgumentError, /already built in/)
    end

    # Every dashboard frame is report_<key> and every dialog is tm-modal-<key>.
    # The search console card, the value search and the funnels draw into that
    # same namespace without being reports.
    %w[search_console facet funnel_1 funnel_anything].each do |reserved|
      it "refuses the key #{reserved.inspect}, which collides with something already on the page" do
        expect { register(key: reserved) }.to raise_error(ArgumentError, /reserved/)
      end
    end

    [ "", "Widgets", "ip addresses", "1st", "ip-addresses", "ip/addresses", "ip.addresses" ].each do |bad|
      it "refuses the key #{bad.inspect}" do
        expect { register(key: bad) }.to raise_error(ArgumentError, /must match/)
      end
    end

    it "refuses a card with no tabs" do
      expect { register(tabs: []) }.to raise_error(ArgumentError, /registers no tabs/)
    end

    it "refuses the same tab key twice" do
      expect { register(tabs: [ tab(key: "ip"), tab(key: "ip", dimension_key: "browser") ]) }
        .to raise_error(ArgumentError, /a tab key twice/)
    end

    it "refuses a tab with no label or no column heading" do
      expect { register(tabs: [ tab(label: "") ]) }.to raise_error(ArgumentError, /has no label/)
      expect { register(tabs: [ tab(label_column: nil) ]) }.to raise_error(ArgumentError, /no label column/)
    end

    # The whole point of checking here rather than leaving it to the dashboard:
    # a typo in an initializer is a boot failure with the tab named, not a 500
    # on a card somebody opens next week.
    it "refuses a metric that does not resolve" do
      expect { register(tabs: [ tab(metrics: %w[vibes]) ]) }
        .to raise_error(ArgumentError, %r{widgets/ip asks for the metric "vibes"})
      expect { register(tabs: [ tab(detail_metrics: %w[visits vibes]) ]) }
        .to raise_error(ArgumentError, /asks for the metric "vibes"/)
    end

    it "refuses a dimension that does not resolve" do
      expect { register(tabs: [ tab(dimension_key: "hairstyle") ]) }
        .to raise_error(ArgumentError, %r{widgets/ip points at "hairstyle"})
    end

    it "refuses a breakdown that does not resolve" do
      breakdown = described_class::Breakdown.new(key: "asn", label: "ASN", dimension_key: "hairstyle",
                                                 label_column: "ASN", detail_metrics: nil)

      expect { register(tabs: [ tab(breakdowns: [ breakdown ]) ]) }
        .to raise_error(ArgumentError, %r{widgets/ip/asn points at "hairstyle"})
    end

    it "refuses a breakdown metric that does not resolve" do
      breakdown = described_class::Breakdown.new(key: "asn", label: "ASN", dimension_key: "browser",
                                                 label_column: "ASN", detail_metrics: %w[vibes])

      expect { register(tabs: [ tab(breakdowns: [ breakdown ]) ]) }
        .to raise_error(ArgumentError, %r{widgets/ip/asn asks for the metric "vibes"})
    end

    it "registers nothing at all when a tab is refused" do
      expect { register(tabs: [ tab(dimension_key: "hairstyle") ]) }.to raise_error(ArgumentError)

      expect(described_class.find_by_key("widgets")).to be_nil
      expect(described_class.cards.map(&:key)).not_to include("widgets")
    end

    # A dimension whose SQL is built out of rows somebody edits has nothing to
    # check until the card is read, so it is taken on trust rather than resolved
    # at boot.
    it "takes a callable dimension key on trust" do
      report = register(tabs: [ tab(dimension_key: -> { "country" }) ])

      expect(report.default_tab.resolved_dimension_key).to eq("country")
    end

    it "still raises for a report nobody registered" do
      register

      expect { described_class.find("vibes") }.to raise_error(ActiveRecord::RecordNotFound)
      expect(described_class.find_by_key("vibes")).to be_nil
    end
  end

  it "opens sources on channels and pages on top pages" do
    expect(described_class.find("sources").default_tab.key).to eq("channels")
    expect(described_class.find("sources").tabs.map(&:key)).to include("channels", "sources", "referrers")
    expect(described_class.find("pages").default_tab.key).to eq("pages")
    expect(described_class.find("pages").tabs.map(&:dimension_key)).to eq(%w[page entry_page exit_page])
    expect(described_class.find("locations").tabs.map(&:dimension_key)).to eq(%w[country region city])
    expect(described_class.find("devices").tabs.map(&:dimension_key)).to include("browser", "os", "device")
    expect(described_class.find("behaviours").default_tab.key).to eq("goals")
  end
end
