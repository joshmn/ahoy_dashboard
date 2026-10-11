module AhoyDashboard
  module Serp
    module Keywords
      class ImportCommand < AhoyDashboard::Command
        Outcome = Data.define(:created, :existing, :rejected)

        def initialize(form:)
          @form = form
          @created = []
          @existing = []
          @rejected = []
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          form.queries.each { |query| import(query) }

          broadcast(:ok, Outcome.new(created: created, existing: existing, rejected: rejected))
        end

        private

        attr_reader :form, :created, :existing, :rejected

        def import(query)
          keyword = SerpKeyword.new(form.shared_attributes.merge(query: query))

          if keyword.save
            attach(keyword)
            created << keyword
          else
            rejected << [ query, keyword.errors.full_messages.to_sentence ]
          end
        rescue ActiveRecord::RecordNotUnique
          existing << query
        end

        def attach(keyword)
          sites.each { |site| Sites::AttachCommand.call(keyword: keyword, site: site, backfill: false) }
        end

        def sites
          @sites ||= SerpSite.where(id: form.chosen_site_ids).to_a
        end
      end
    end
  end
end
