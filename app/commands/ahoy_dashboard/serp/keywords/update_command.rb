module AhoyDashboard
  module Serp
    module Keywords
      class UpdateCommand < AhoyDashboard::Command
        Outcome = Data.define(:keyword, :attached, :backfilled, :archived)

        KEPT_FIELDS = %i[query engine device language locations pages frequency tags source last_checked_at].freeze

        def initialize(keyword:, form:)
          @keyword = keyword
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          keyword.assign_attributes(form.record_attributes)
          return copy_errors unless keyword.valid?

          outcome = SerpKeyword.transaction { save }

          broadcast(:ok, outcome)
        rescue ActiveRecord::RecordNotUnique
          form.errors.add(:base, KeywordForm::DUPLICATE_MESSAGE)
          broadcast(:duplicate, form)
        end

        private

        attr_reader :keyword, :form

        def save
          moving = keyword.search_changed? && keyword.runs.exists?
          old = KEPT_FIELDS.index_with { |field| keyword.attribute_in_database(field) }
          old_site_ids = keyword.keyword_targets.pluck(:site_id)

          keyword.last_checked_at = nil if keyword.search_changed?
          keyword.save!
          archived = archive(old, old_site_ids) if moving

          Outcome.new(keyword: keyword, archived: archived, **sync_targets)
        end

        def archive(old, site_ids)
          copy = SerpKeyword.new(old.merge(enabled: false))
          copy.save!(validate: false)

          SerpRun.where(keyword_id: keyword.id).update_all(keyword_id: copy.id)
          site_ids.each do |site_id|
            target = SerpKeywordTarget.create!(keyword: copy, site_id: site_id)
            SerpCheck.where(keyword_id: keyword.id, site_id: site_id).update_all(keyword_id: copy.id, target_id: target.id)
          end

          copy
        end

        def sync_targets
          wanted = form.chosen_site_ids
          keyword.keyword_targets.where.not(site_id: wanted).destroy_all

          attached = 0
          backfilled = 0
          SerpSite.where(id: wanted - keyword.keyword_targets.pluck(:site_id)).find_each do |site|
            Sites::AttachCommand.call(keyword: keyword, site: site) do
              on(:ok) do |outcome|
                attached += 1
                backfilled += outcome.backfilled
              end
            end
          end

          { attached: attached, backfilled: backfilled }
        end

        def copy_errors
          keyword.errors.messages.each do |attribute, messages|
            messages.each { |message| form.errors.add(attribute, message) }
          end

          broadcast(:invalid, form)
        end
      end
    end
  end
end
