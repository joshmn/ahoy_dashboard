module AhoyDashboard
  module Assistant
    module Tools
      class BaseTool < AhoyDashboard::LLM::Tool
        PERIOD_HELP = "A named window. Leave out period, from, to and days for the last 30 days. " \
                      "Ignored when from or to is given.".freeze
        FROM_HELP = "Start of the window as YYYY-MM-DD, for a stretch the named windows cannot " \
                    "say. Both ends are included. from and to win over period and days.".freeze
        TO_HELP = "End of the window as YYYY-MM-DD, included.".freeze
        DAYS_HELP = "How many days back to read, counting today, up to #{Window::MAX_DAYS}. Only used when " \
                    "period, from and to are all left out. Prefer period or from and to.".freeze
        FILTERS_HELP = "The dashboard filters to read through, in place of the conversation's own. Leave it " \
                       "out to read what the conversation is about. Pass an empty list for the whole site. " \
                       "Each is a dimension key from breakdown, an operator (%s) and a value. Filters that " \
                       "share a group number are alternatives, and any one of them is enough. Every other " \
                       "filter, and every group, must all hold. Leave group out for a plain filter.".freeze
        GROUP_HELP = "Optional. Filters with the same number are alternatives joined by or.".freeze

        class << self
          def feature
            nil
          end

          def available?
            feature.nil? || Installation.installed?(feature)
          end

          def label(text = nil)
            @label = text if text
            @label || tool_name.humanize.downcase
          end

          def window_params(schema)
            schema.string :period, description: PERIOD_HELP, required: false, enum: Window.keys
            schema.string :from, description: FROM_HELP, required: false, format: "date"
            schema.string :to, description: TO_HELP, required: false, format: "date"
            schema.integer :days, description: DAYS_HELP, required: false
            schema.array :filters, description: format(FILTERS_HELP, AhoyDashboard::Filter::OPERATORS.keys.join(", ")),
                                   required: false,
                                   items: {
                                     "type" => "object",
                                     "properties" => {
                                       "dimension" => { "type" => "string",
                                                        "description" => "A dimension key, as breakdown lists them" },
                                       "operator" => { "type" => "string", "enum" => AhoyDashboard::Filter::OPERATORS.keys },
                                       "value" => { "type" => "string" },
                                       "group" => { "type" => "integer", "minimum" => 0, "description" => GROUP_HELP }
                                     },
                                     "required" => %w[dimension value]
                                   }
          end
        end

        def initialize(views: nil, slice: Slice.new)
          super()
          @views = views
          @slice = slice
        end

        def execute(**arguments)
          answer(**arguments)
        rescue Window::UnknownPeriod => e
          unknown_period(e)
        rescue Slice::InvalidFilters => e
          invalid_filters(e)
        end

        private

        attr_reader :views, :slice

        def show(view)
          case views&.accept(view)
          when :drawn then { drawn: true }.merge(cut(view))
          when :full
            { drawn: false,
              not_drawn: "the screen already holds #{Views::LIMIT} charts and tables for this answer, so this one is not shown" }
          else { drawn: false }
          end
        end

        def cut(view)
          if view.rows_cut.positive?
            { not_drawn: "only the first #{View::MAX_ROWS} rows are on the screen. the other #{view.rows_cut} are not" }
          elsif view.points_cut.positive?
            { not_drawn: "only the last #{View::MAX_POINTS} points are on the screen. the #{view.points_cut} before them are not" }
          else
            {}
          end
        end

        def window(period: nil, from: nil, to: nil, days: nil, filters: nil, **rest)
          Window.call(period: period, from: from, to: to, days: days, slice: slice.with(filters), **rest)
        end

        def unknown_period(error)
          { error: "no window called #{error.message}", periods: Window.described }
        end

        def invalid_filters(error)
          {
            error: "nothing was read, because of the filters: #{error.message}",
            dimensions: AhoyDashboard::Dimension.filterable.map(&:key).reject { |key| Assistant.withheld?(key) },
            operators: AhoyDashboard::Filter::OPERATORS.keys,
            groups: "filters that share a group number are alternatives, and any one is enough. different groups " \
                    "must all hold. group is a whole number from 0 up, or left out for a plain filter."
          }
        end

        def subtitle(*parts, read:)
          [ *parts, read.filter_sentence.presence ].reject(&:blank?).join(", ")
        end

        def unfiltered_subtitle(text, read)
          read.filter_labels.empty? ? text : "#{text}. The whole site, filters do not apply here"
        end

        def unfiltered(read)
          return {} if read.filter_labels.empty?

          { filters: "none, the whole site", filters_not_applied: read.filter_labels,
            note_on_filters: "this data has no visitor behind it, so no dashboard filter can apply to it. " \
                             "say so if the question was about the filtered slice." }
        end

        def rounded(value, places = 2)
          value.to_f.round(places)
        end

        def row_limit(value)
          value.to_i.clamp(1, 50)
        end

        def routes
          AhoyDashboard.routes
        end

        def dashboard_path(window, **extra)
          routes.root_path(window.link_params(**extra))
        end

        def explore_path(window, **extra)
          routes.explore_path(window.link_params(**extra))
        end
      end
    end
  end
end
