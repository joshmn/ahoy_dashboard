module AhoyDashboard
  module Assistant
    module Tools
      class Breakdown < BaseTool
        DEFAULT_LIMIT = 10

        label "a breakdown"

        desc "Call this when the question is about which pages, sources, countries, devices, goals or " \
             "other values brought the traffic. It ranks one dimension by visitors. Call it with no " \
             "dimension to get the whole list of dimensions this site has, which is longer than you would guess."

        params do
          string :dimension, description: "The dimension key to group by, e.g. page or source, from the list " \
                                          "this tool returns when called with no dimension",
                             required: false
          integer :limit, description: "How many rows, from 1 to 50. Defaults to 10.", required: false
          AhoyDashboard::Assistant::Tools::BaseTool.window_params(self)
        end

        private

        def answer(dimension: nil, limit: DEFAULT_LIMIT, **asked)
          return { dimensions: available } if dimension.blank?

          found = AhoyDashboard::Dimension.find_by_key(dimension.to_s)
          return { error: "no dimension called #{dimension}", dimensions: available } if found.nil?
          if Assistant.withheld?(found.key)
            return { error: "#{found.label} is kept out of the assistant by the site's owner", dimensions: available }
          end

          read = window(**asked)
          result = AhoyDashboard::BreakdownQuery.call(
            scope: read.scope, dimension: found, limit: row_limit(limit)
          )
          rows = result.rows.map { |row| { name: row.label, visitors: row.metrics["visitors"] } }

          drawn = draw(read, found, rows)

          read.to_h.merge(dimension: found.key, label: found.label, **drawn,
                          rows: rows, more: result.more)
        end

        def draw(read, dimension, rows)
          show(
            View.table(
              title: "#{dimension.label}, #{read.label}",
              subtitle: subtitle("By visitors", read: read),
              columns: [ { key: :name, label: dimension.label },
                         { key: :visitors, label: "Visitors", align: "end" } ],
              rows: rows,
              path: explore_path(read, dimension: dimension.key),
              path_label: "Open in Explore"
            )
          )
        end

        def available
          AhoyDashboard::Dimension.with_properties
            .reject { |dimension| Assistant.withheld?(dimension.key) }
            .map { |dimension| { key: dimension.key, label: dimension.label } }
        end
      end
    end
  end
end
