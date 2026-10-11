module AhoyDashboard
  module Seo
    class AiVisibilityPresenter < BasePresenter
      COLORS = {
        "openai" => "var(--green-t)", "anthropic" => "var(--accent)",
        "gemini" => "var(--warn-t)", "perplexity" => "var(--red-t)"
      }.freeze
      FALLBACK_COLOR = "var(--t2)".freeze
      DASHES = [ nil, "6 4", "2 3", "10 3 2 3" ].freeze
      PLOT_HEIGHT = 120
      PLOT_WIDTH = 640

      Line = Data.define(:assistant, :model, :label, :color, :dash, :path, :latest)

      attr_reader :assistant, :model

      def initialize(assistant: nil, model: nil, **options)
        super(**options)
        @assistant = assistant.presence
        @model = @assistant && model.presence
      end

      def title
        assistant ? "#{surface.title}: #{assistant_label}" : surface.title
      end

      def assistant_label
        return "All assistants" unless assistant

        AiVisibility.target_label(assistant, model)
      end

      def assistant_options
        options = [ menu_option(nil, nil) ]

        AiVisibility::NAMES.each do |name|
          options << menu_option(name, nil)
          models = models_by_assistant.fetch(name, [])
          models.each { |asked| options << menu_option(name, asked) } if models.many?
        end

        options
      end

      def tiles
        [
          Tile.new(label: "Mention rate", value: percent(result.mention_rate), note: answers_note),
          Tile.new(label: "Citation rate", value: percent(result.citation_rate), note: answers_note),
          Tile.new(label: "Prompts", value: number(result.prompts), note: "in the set"),
          Tile.new(label: "Answers", value: number(result.answers), note: answers_tile_note),
          Tile.new(label: "Used this month", value: number(result.used_this_month), note: cap_note)
        ]
      end

      def answers_note
        "of #{pluralize(result.answers, "answer")}"
      end

      def answers_tile_note
        return range_label if result.failed.zero?

        "#{range_label}, #{result.failed} failed"
      end

      def cap_note
        result.capped? ? "of #{number(result.monthly_cap)} requests" : "no cap"
      end

      def enabled?
        AiVisibility.enabled?
      end

      def asked?
        configured_targets.any?
      end

      def prompts?
        result.prompts.positive?
      end

      def settings_path
        routes.edit_settings_ai_visibility_path
      end

      def setup_notice
        unless enabled?
          return { title: "Turn on AI visibility to get started",
                   hint: "AI visibility is off. Every answer is a paid request, so it stays off until you " \
                         "switch it on under Settings, Features." }
        end
        return setup_step("Turn on an assistant to get started", "Every assistant that is on and has a key is asked your prompts.", "Set up an assistant") unless asked?
        return setup_step("Write your prompts to get started", "Write the questions you want to show up in, one per line.", "Write prompts") unless prompts?

        nil
      end

      def empty_state
        hint = "Answers show here after the next run. Runs happen #{AiVisibility::FREQUENCIES.fetch(AiVisibility.frequency)[:label].downcase}, or press Run now."
        return { title: "No answers in this range", hint: hint, action: widen_action } if narrow?

        { title: "No answers in this range", hint: hint }
      end

      def skipped_note
        run = result.skipped_run
        return if run.nil?

        "On #{on_label(run.started_at.in_time_zone(AhoyDashboard.time_zone).to_date)}, nothing was sent. #{run.skip_reason}"
      end

      def requests_per_run
        result.prompts * configured_targets.size
      end

      def run_path
        routes.seo_ai_visibility_runs_path
      end

      def run_reason
        return "AI visibility is off. Turn it on under Settings, Features." unless enabled?
        return "No assistant is on with a key." unless asked?
        return "There are no prompts." unless prompts?

        left = AiVisibility.remaining
        return if requests_per_run <= left

        "A run needs #{requests_per_run} requests and #{left} are left this month."
      end

      def run_fix
        enabled? ? { label: "AI visibility settings", url: settings_path } : nil
      end

      def run_confirm
        "Ask every prompt now? This sends #{pluralize(requests_per_run, "paid request")} and counts against the monthly cap."
      end

      def all_prompts
        AiVisibility::Prompt.ordered.to_a
      end

      def by_assistant
        result.by_assistant
      end

      def missing_prompts
        result.missing_prompts
      end

      def cited_instead
        result.cited_instead
      end

      def position_of(row)
        row.average_position.nil? ? DASH : decimal(row.average_position)
      end

      def prompt_path(prompt)
        routes.seo_ai_visibility_prompt_path(prompt, **carried)
      end

      def csv_tables
        [
          CsvTable.new(key: "assistants", label: "By assistant and model",
                       headers: [ "Assistant", "Model", "Answers", "Mentioned", "Cited", "Mention rate",
                                  "Citation rate", "Average position" ]) do
            by_assistant.map do |row|
              [ row.label, row.model, row.answers, row.mentioned, row.cited, csv_percent(row.mention_rate),
                csv_percent(row.citation_rate), row.average_position&.round(1) ]
            end
          end,
          CsvTable.new(key: "missing_prompts", label: "Prompts you don't show up in",
                       headers: [ "Prompt", "Models asked", "Last asked" ]) do
            missing_prompts.map { |row| [ row.prompt.text, row.asked, csv_time(row.last_asked_at) ] }
          end,
          CsvTable.new(key: "cited_instead", label: "Who gets cited instead",
                       headers: [ "Domain", "Answers citing it", "Share of answers" ]) do
            cited_instead.map { |row| [ row.domain, row.answers, csv_percent(row.share) ] }
          end
        ]
      end

      def asked_label(time)
        when_label(time)
      end

      def dates
        @dates ||= result.series.map(&:on).uniq.sort
      end

      def charted?
        dates.size >= AhoyDashboard::SeoHelper::PLOT_MINIMUM
      end

      def lines
        points = result.series.group_by { |point| [ point.assistant, point.model ] }
        order = ->(key) { [ AiVisibility::NAMES.index(key.first) || AiVisibility::NAMES.size, key.first, key.last.to_s ] }

        points.keys.sort_by(&order).group_by(&:first).flat_map do |name, keys|
          keys.each_with_index.map do |key, index|
            by_day = points[key].index_by(&:on)
            Line.new(assistant: name, model: key.last, label: AiVisibility.target_label(*key),
                     color: COLORS.fetch(name, FALLBACK_COLOR), dash: DASHES[index % DASHES.size],
                     path: path_for(dates.map { |on| by_day[on]&.rate }), latest: points[key].max_by(&:on))
          end
        end
      end

      def first_date
        on_label(dates.first)
      end

      def last_date
        on_label(dates.last)
      end

      def plot_height
        PLOT_HEIGHT
      end

      private

      def setup_step(title, hint, label)
        { title: title, hint: hint, action: { label: label, url: settings_path, data: TOP } }
      end

      def carried
        { assistant: assistant, model: model }.compact
      end

      def menu_option(name, asked)
        {
          label: menu_label(name, asked),
          url: surface.path(query.to_query.merge(site_param).merge(assistant: name, model: asked).compact),
          active: name == assistant && asked == model
        }
      end

      def menu_label(name, asked)
        return "All assistants" unless name
        return AiVisibility.label(name) unless asked

        "#{AiVisibility.label(name)}, #{asked}"
      end

      def models_by_assistant
        memo(:models_by_assistant) do
          asked = AiVisibility::Answer.distinct.pluck(:assistant, :model)
          current = configured_targets.map { |target| [ target.assistant, target.model ] }

          (asked + current).uniq.sort_by(&:last).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
        end
      end

      def configured_targets
        memo(:configured_targets) { AiVisibility.targets }
      end

      def link_param
        super.merge(carried)
      end

      def path_for(values)
        step = dates.size > 1 ? PLOT_WIDTH.to_f / (dates.size - 1) : 0
        drawing = false

        values.each_with_index.map do |value, index|
          if value.nil?
            drawing = false
            next
          end

          x = (index * step).round(1)
          y = (PLOT_HEIGHT - (value * (PLOT_HEIGHT - 4)) - 2).round(1)
          command = drawing ? "L" : "M"
          drawing = true
          "#{command}#{x} #{y}"
        end.select { |value| value }.join(" ")
      end
    end
  end
end
