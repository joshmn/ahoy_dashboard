module AhoyDashboard
  module Serp
    module Checks
      class RunCommand < AhoyDashboard::Command
        Outcome = Data.define(:run, :checks, :citations, :units)

        OFF_MESSAGE = "serp tracking is switched off".freeze
        NOTHING_MESSAGE = "no page of results came back".freeze
        PAUSED_MESSAGE = "this keyword is paused".freeze
        NO_SITES_MESSAGE = "this keyword has no site to look for".freeze

        def initialize(keyword:, location:, provider: :unset, now: Time.current)
          @keyword = keyword
          @place = Location.parse(location)
          @provider = provider
          @now = now
          @failures = []
          @spent = 0
        end

        def call
          return broadcast(:skipped, OFF_MESSAGE) unless Serp.enabled?
          return broadcast(:skipped, "#{adapter_class.adapter_name} has no credentials") unless configured?
          return broadcast(:skipped, PAUSED_MESSAGE) unless keyword.enabled?
          return broadcast(:skipped, NO_SITES_MESSAGE) if targets.empty?
          return broadcast(:capped, provider) unless spend.reserve

          run = start_run
          results = fetch(run)
          return exhausted(run) if results.empty?

          finish(run, Result.combine(results))
        rescue AuthError, QuotaError, Error => e
          broken(e)
        ensure
          @spend&.settle(@spent)
        end

        private

        attr_reader :keyword, :place, :now, :failures, :run

        def provider
          @provider = SerpProvider.current if @provider == :unset
          @provider
        end

        def adapter_class
          @adapter_class ||= provider&.adapter_class || Serp.adapter_class
        end

        def adapter
          @adapter ||= adapter_class.new
        end

        def configured?
          adapter_class.configured?
        end

        def units
          @units ||= adapter_class.cost_units(pages: keyword.pages)
        end

        def spend
          @spend ||= Spend.new(provider: provider, units: units, kind: :checks,
                               name: adapter_class.adapter_name, now: now)
        end

        def targets
          @targets ||= keyword.keyword_targets.includes(:site).merge(SerpKeywordTarget.tracked).to_a
        end

        def start_run
          @run = keyword.runs.create!(
            provider: adapter_class.adapter_name, engine: keyword.engine, query: keyword.query,
            location: place.to_s, device: keyword.device, language: keyword.language,
            requested_pages: keyword.pages, status: :pending, checked_at: now
          )
        end

        def fetch(run)
          adapter_class.requests_for(pages: keyword.pages).map do |request|
            page = build_page(run, request)
            fetch_page(page, request)
          end.select { |value| value }
        end

        def build_page(run, request)
          run.run_pages.create!(
            page_number: request.page, start: request.start, depth: request.depth, status: :pending,
            request_params: {
              engine: keyword.engine, query: keyword.query, location: place.to_s,
              device: keyword.device, language: keyword.language, start: request.start,
              depth: request.depth
            }
          )
        end

        def fetch_page(page, request)
          result = adapter.search(query: keyword.query, location: place, request: request,
                                  device: keyword.device, language: keyword.language,
                                  engine: keyword.engine)
          @spent += result.cost_units.to_i
          store(page, result)
          result
        rescue AuthError, QuotaError => e
          page.update!(status: :failed, error_message: e.message.to_s.first(255))
          raise
        rescue Error => e
          page.update!(status: :failed, error_message: e.message.to_s.first(255))
          failures << e.message
          nil
        end

        def store(page, result)
          trimmed = SerpRunPage.trim(result.raw, provider: result.provider)

          page.update!(status: :success, provider_search_id: result.provider_search_id,
                       response: trimmed, raw_bytes: result.raw.to_json.bytesize)
        end

        def finish(run, combined)
          checks = targets.map { |target| record_check(run, target, combined) }
          citations = record_citations(run, combined)
          Results::StoreCommand.call(run: run, result: combined)

          run.update!(status: failures.any? ? :partial : :success, cost_units: combined.cost_units,
                      error_message: failures.first&.first(255))
          keyword.update!(last_checked_at: now)
          spend.settle(@spent, used: true)
          provider&.clear_error!

          broadcast(:ok, Outcome.new(run: run, checks: checks, citations: citations,
                                     units: combined.cost_units))
        end

        def record_check(run, target, combined)
          site = target.site
          rank = combined.rank_for(site.domain, match_subdomains: site.match_subdomains)
          overview = combined.ai_overview
          source = overview.source_for(site.domain, match_subdomains: site.match_subdomains)

          upsert_check(run, target, {
            position: rank&.position, page: rank&.page, url: rank&.link,
            ai_overview_present: overview.shown?,
            ai_overview_cited: overview.shown? && source.present?,
            ai_overview_citation_position: source ? overview.sources.index(source) + 1 : nil,
            ai_overview_source_count: overview.sources.size,
            status: :success, error_message: nil
          })
        end

        def upsert_check(run, target, attributes)
          check = target.checks.find_or_initialize_by(run: run)
          check.assign_attributes(attributes.merge(
            keyword: keyword, site_id: target.site_id, location: place.to_s, checked_at: run.checked_at
          ))
          check.save!
          check
        end

        def record_citations(run, combined)
          return [] unless combined.ai_overview.shown?

          run.ai_citations.destroy_all
          combined.ai_overview.sources.each_with_index.map do |source, index|
            run.ai_citations.create!(slot: index + 1, link: source.link, domain: source.domain,
                                     title: source.title, checked_at: run.checked_at)
          end
        end

        def exhausted(run)
          message = failures.first.presence || NOTHING_MESSAGE
          fail_run(run, message)
          spend.settle(@spent)

          broadcast(:failed, message)
        end

        def broken(error)
          fail_run(run, error.message) if run
          @spend&.settle(@spent)
          provider&.record_error!(error.message)

          return broadcast(:rate_limited, error.message) if error.is_a?(QuotaError)

          broadcast(:failed, error.message)
        end

        def fail_run(run, message)
          run.update!(status: :failed, error_message: message.to_s.first(255))
          targets.each do |target|
            upsert_check(run, target, { status: :failed, error_message: message.to_s.first(255) })
          end
        end
      end
    end
  end
end
