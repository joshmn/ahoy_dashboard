module AhoyDashboard
  module Sql
    class ExcludedTraffic
      class << self
        def enabled?
          InternalAddresses.enabled? || AhoyDashboard::Exclusion.active.any?
        end

        def exclusions
          AhoyDashboard::Exclusion.active
        end

        def condition(floor: nil)
          parts = [ InternalAddresses.condition ]
          parts.concat(exclusions.map { |exclusion| match_sql(exclusion.to_blocks, floor: floor) })
          parts = parts.compact
          return nil if parts.empty?

          parts.map { |part| "COALESCE((#{part}), false)" }.join(" OR ")
        end

        def exclude(relation, floor: nil)
          sql = condition(floor: floor)

          sql.nil? ? relation : relation.where(Arel.sql("NOT (#{sql})"))
        end

        def only(relation, floor: nil)
          sql = condition(floor: floor)

          sql.nil? ? relation.none : relation.where(Arel.sql("(#{sql})"))
        end

        def match_sql(filters, floor: nil)
          return blocks_sql(filters, floor) if filters.is_a?(AhoyDashboard::FilterBlocks)

          groups = filters.groups
          return nil if groups.empty? || groups.any? { |group| group.kind == :exit }

          visit = groups.select { |group| group.kind == :visit }.map { |group| group_sql(group) }
          events = [ :session, :view ].map do |kind|
            family = groups.select { |group| group.kind == kind }
            exists_sql(family, floor) if family.any?
          end.select { |value| value }

          "(#{(visit + events).join(' AND ')})"
        end

        private

        def blocks_sql(blocks, floor)
          parts = blocks.map { |block| match_sql(block, floor: floor) }
          return nil if parts.empty? || parts.any?(&:nil?)

          "(#{parts.join(' OR ')})"
        end

        def group_sql(group, candidate: false)
          "(#{group.map { |filter| candidate ? filter.candidate_predicate : filter.predicate }.join(' OR ')})"
        end

        def exists_sql(family, floor)
          conditions = [ "ahoy_events.visit_id = ahoy_visits.id" ]
          conditions << "ahoy_events.time >= #{Sql.timestamp(floor)}" if floor
          conditions.concat(family.map { |group| group_sql(group, candidate: true) })

          "EXISTS (SELECT 1 FROM #{AhoyDashboard.event.quoted_table_name} WHERE #{conditions.join(' AND ')})"
        end
      end
    end
  end
end
