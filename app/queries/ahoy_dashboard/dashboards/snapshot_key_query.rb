# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotKeyQuery
      VERSION = 1
      DEFINITIONS = [Goal, Funnel, FunnelStep, SavedQuery, Annotation, Exclusion,
        PageGroup, Property, Segment, Setting, GoogleAccount].freeze

      class << self
        def call(query:)
          new(query: query).call
        end
      end

      def initialize(query:)
        @query = query
      end

      def call
        fingerprint = ["dashboard/snapshot", VERSION, AhoyDashboard::VERSION,
          AhoyDashboard.time_zone.name, query.range.begin.iso8601(9), query.range.end.iso8601(9),
          query.scope.visits.to_sql, query.scope.events.to_sql, definitions,
          source_identity(AhoyDashboard.visit), source_identity(AhoyDashboard.event), installed_features,
          reports, Dimension.registry.values.map { |dimension| dimension_signature(dimension) }]
        AnalyticsCache.key(key: fingerprint, connection: Record.connection)
      end

      private

      attr_reader :query

      def source_identity(model)
        AnalyticsCache.key(key: [model.name, model.table_name, model.all.to_sql], connection: model.connection)
      end

      def definitions
        projections = DEFINITIONS.map do |model|
          if Installation.table?(model.table_name)
            "(SELECT md5(coalesce(string_agg(md5(row_to_json(d)::text), '' ORDER BY d.id), '')) " \
              "FROM (#{model.all.reorder(nil).to_sql}) d)"
          else
            "NULL::text"
          end
        end
        digests = Record.uncached { Record.connection.select_rows("SELECT #{projections.join(', ')}").first }
        [projections, digests]
      end

      def installed_features
        Installation::FEATURES.map { |feature| [feature.name, feature.installed?] }
      end

      def reports
        Report.grid_cards.map do |report|
          tabs = report.tabs.map do |tab|
            [tab.key, tab.label, tab.resolved_dimension_key, tab.metrics, tab.detail_metrics,
              tab.label_column, tab.breakdown_options.map(&:to_h)]
          end
          [report.key, report.title, report.default_tab_key, report.wide?, tabs,
            dimension_signature(report.tab.dimension)]
        end
      end

      def dimension_signature(dimension)
        [dimension.key, dimension.label, dimension.scope, dimension.sql.to_s,
          dimension.exclude.to_s, dimension.page_views_only?, dimension.unknown_label]
      end
    end
  end
end
