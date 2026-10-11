module AhoyDashboard
  module AiVisibility
    class ReportQuery
      CITED_INSTEAD_LIMIT = 20

      AssistantRow = Data.define(:assistant, :model, :answers, :mentioned, :cited, :average_position) do
        def label
          AiVisibility.label(assistant)
        end

        def target_label
          AiVisibility.target_label(assistant, model)
        end

        def mention_rate
          answers.zero? ? 0.0 : mentioned.to_f / answers
        end

        def citation_rate
          answers.zero? ? 0.0 : cited.to_f / answers
        end
      end

      MissingPrompt = Data.define(:prompt, :asked, :last_asked_at)

      DomainRow = Data.define(:domain, :answers, :share)

      Point = Data.define(:on, :assistant, :model, :answers, :mentioned) do
        def rate
          answers.zero? ? 0.0 : mentioned.to_f / answers
        end
      end

      Result = Data.define(:range, :assistant, :model, :answers, :mentioned, :cited, :failed, :prompts, :used_this_month,
                           :monthly_cap, :by_assistant, :series, :missing_prompts, :cited_instead, :skipped_run) do
        def any?
          answers.positive?
        end

        def mention_rate
          answers.zero? ? 0.0 : mentioned.to_f / answers
        end

        def citation_rate
          answers.zero? ? 0.0 : cited.to_f / answers
        end

        def capped?
          monthly_cap.positive?
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(range:, assistant: nil, model: nil, now: Time.current)
        @range = range
        @assistant = assistant.presence&.to_s
        @model = model.presence&.to_s
        @now = now
      end

      def call
        groups = answer_groups
        assistants = by_assistant(groups)
        mentioned = assistants.sum(&:mentioned)
        cited = assistants.sum(&:cited)
        answers = assistants.sum(&:answers)

        Result.new(
          range: range, assistant: assistant, model: model, answers: answers, mentioned: mentioned, cited: cited,
          failed: groups.sum { |row| row[2] == "failed" ? row[3].to_i : 0 }, prompts: Prompt.count,
          used_this_month: AiVisibility.used_this_month(now: now), monthly_cap: AiVisibility.monthly_cap,
          by_assistant: assistants, series: series, missing_prompts: missing_prompts,
          cited_instead: cited_instead(answers), skipped_run: skipped_run
        )
      end

      private

      attr_reader :range, :assistant, :model, :now

      def scoped(relation)
        relation.in_range(range).for_assistant(assistant).for_model(model)
      end

      def answered
        scoped(Answer.success)
      end

      def answer_groups
        scoped(Answer.completed).group(:assistant, :model, :status).pluck(
          :assistant,
          :model,
          :status,
          Arel.sql("count(*)"),
          Arel.sql("count(*) filter (where mentioned)"),
          Arel.sql("count(*) filter (where cited)"),
          Arel.sql("avg(position) filter (where cited and position is not null)")
        )
      end

      def by_assistant(groups)
        rows = groups.map do |name, asked, status, answers, mentioned, cited, position|
          next unless status == "success"

          AssistantRow.new(assistant: name, model: asked, answers: answers.to_i, mentioned: mentioned.to_i,
                           cited: cited.to_i, average_position: position&.to_f)
        end.select { |value| value }

        rows.sort_by { |row| [ AiVisibility::NAMES.index(row.assistant) || AiVisibility::NAMES.size, row.model.to_s ] }
      end

      def local_day
        @local_day ||= begin
          zone = ActiveRecord::Base.connection.quote(AhoyDashboard.time_zone.tzinfo.name)

          Arel.sql("(asked_at at time zone 'UTC' at time zone #{zone})::date")
        end
      end

      def series
        answered.group(:assistant, :model, local_day).order(local_day).pluck(
          local_day, :assistant, :model, Arel.sql("count(*)"), Arel.sql("count(*) filter (where mentioned)")
        ).map do |on, name, asked, answers, mentioned|
          Point.new(on: on, assistant: name, model: asked, answers: answers.to_i, mentioned: mentioned.to_i)
        end
      end

      def missing_prompts
        latest = answered.select(
          "distinct on (prompt_id, assistant, model) prompt_id, assistant, model, mentioned, asked_at"
        ).order(:prompt_id, :assistant, :model, asked_at: :desc, id: :desc)

        rows = Answer.unscoped.from(latest, :latest).group("latest.prompt_id")
          .having("not bool_or(latest.mentioned)")
          .order(Arel.sql("max(latest.asked_at) desc"))
          .pluck(Arel.sql("latest.prompt_id"), Arel.sql("count(*)"), Arel.sql("max(latest.asked_at)"))

        prompts = Prompt.where(id: rows.map(&:first)).index_by(&:id)

        rows.map do |prompt_id, asked, last_asked_at|
          prompt = prompts[prompt_id]
          prompt && MissingPrompt.new(prompt: prompt, asked: asked.to_i, last_asked_at: last_asked_at)
        end.select { |value| value }
      end

      def cited_instead(answers)
        return [] if answers.zero?

        Source.joins(:answer).merge(answered)
          .where(ours: false).where.not(domain: [ nil, "" ])
          .group(:domain)
          .order(Arel.sql("count(distinct ahoy_dashboard_ai_visibility_sources.answer_id) desc, domain asc"))
          .limit(CITED_INSTEAD_LIMIT)
          .pluck(:domain, Arel.sql("count(distinct ahoy_dashboard_ai_visibility_sources.answer_id)"))
          .map { |domain, count| DomainRow.new(domain: domain, answers: count.to_i, share: count.to_f / answers) }
      end

      def skipped_run
        Run.skipped.where(started_at: range).recent.first
      end
    end
  end
end
