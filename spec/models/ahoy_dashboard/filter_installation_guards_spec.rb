# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Filter installation guards" do
  let(:connection) { ActiveRecord::Base.connection }

  around do |example|
    example.run
  ensure
    connection.schema_cache.clear!
    [AhoyDashboard::Exclusion, AhoyDashboard::Segment, AhoyDashboard::PageGroup,
     AhoyDashboard::Property].each(&:reset_column_information)
    AhoyDashboard::Current.reset
  end

  shared_examples "an installation-aware filter reader" do
    it "uses its empty value when the installation table is missing" do
      connection.rename_table(table, "uninstalled_filter_table")
      connection.schema_cache.clear!
      AhoyDashboard::Current.reset

      expect(reader.call).to eq(missing_value)
    end

    it "propagates a real SQL failure from an installed table" do
      connection.rename_column(table, column, "unavailable")

      expect { connection.transaction(requires_new: true) { reader.call } }
        .to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  [
    [AhoyDashboard::Exclusion, :listed, :name, []],
    [AhoyDashboard::Exclusion, :active, :enabled, []],
    [AhoyDashboard::Segment, :listed, :position, []],
    [AhoyDashboard::Segment, :default, :applied_by_default, nil],
    [AhoyDashboard::PageGroup, :listed, :position, []],
    [AhoyDashboard::Property, :dimension_keys, :key, []],
    [AhoyDashboard::Property, :default_dimension_key, :key, "prop:property"]
  ].each do |model, method, required_column, fallback|
    context "#{model.name}.#{method}" do
      let(:table) { model.table_name }
      let(:column) { required_column }
      let(:reader) { -> { model.public_send(method) } }
      let(:missing_value) { fallback }

      include_examples "an installation-aware filter reader"
    end
  end

  context "filterable dimensions" do
    let(:table) { AhoyDashboard::Property.table_name }
    let(:column) { :enabled }
    let(:reader) { -> { AhoyDashboard::Dimension.filterable } }
    let(:missing_value) do
      (AhoyDashboard::Dimension::ALL + AhoyDashboard::Dimension.registry.values).select(&:filterable?)
    end

    include_examples "an installation-aware filter reader"
  end

  context "the default URL filters" do
    let(:table) { AhoyDashboard::Segment.table_name }
    let(:column) { :applied_by_default }
    let(:reader) { -> { AhoyDashboard::QueryForm.from_params({}).filters.to_a } }
    let(:missing_value) { [] }

    include_examples "an installation-aware filter reader"
  end

  context "property discovery" do
    let(:table) { AhoyDashboard::Property.table_name }
    let(:column) { :enabled }
    let(:reader) { -> { AhoyDashboard::PropertyKeysQuery.call(scope: dash_scope(range: dash_day_range(2026, 8, 10))) } }
    let(:missing_value) { [] }

    include_examples "an installation-aware filter reader"
  end
end
