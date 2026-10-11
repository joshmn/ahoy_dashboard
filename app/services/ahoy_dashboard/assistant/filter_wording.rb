module AhoyDashboard
  module Assistant
    module FilterWording
      class << self
        def labels(filters)
          groups = filters.groups

          groups.map do |group|
            label = group_label(group)
            groups.size > 1 && !group.single? ? "(#{label})" : label
          end
        end

        def sentence(filters)
          labels(filters).join(" and ")
        end

        def hidden_traffic(query)
          return { hidden_traffic: "shown" } if query.include_internal?

          names = []
          names << "internal addresses" if AhoyDashboard::Sql::InternalAddresses.enabled?
          names.concat(AhoyDashboard::Sql::ExcludedTraffic.exclusions.map(&:name))

          { hidden_traffic: "excluded", hidden_by: names.presence }.compact
        end

        private

        def group_label(group)
          withheld, open = group.partition { |filter| Assistant.withheld?(filter.dimension.key) }
          return group.label if withheld.empty?

          kept_out = withheld.map { |filter| filter.dimension.filter_label }.uniq
                             .map { |label| "#{label}, kept out of the assistant" }

          [ *open.map(&:label), *kept_out ].join(" or ")
        end
      end
    end
  end
end
