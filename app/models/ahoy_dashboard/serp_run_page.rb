module AhoyDashboard
  class SerpRunPage < AhoyDashboard::Record
    enum :status, { pending: 0, success: 1, failed: 2 }, validate: true

    belongs_to :run, class_name: "AhoyDashboard::SerpRun", inverse_of: :run_pages

    validates :page_number, numericality: { only_integer: true, greater_than_or_equal_to: 1 },
              uniqueness: { scope: :run_id }
    validates :start, :depth, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    def self.trim(payload, provider:)
      Serp.adapter_class(provider).trim(payload)
    rescue Serp::Error
      {}
    end

    def request
      Serp::Adapters::BaseAdapter::Request.new(page: page_number, start: start, depth: depth)
    end

    def result
      return nil if response.blank?

      adapter.parse_payload(response, query: run.query, location: run.location, request: request,
                                      device: run.device, language: run.language, engine: run.engine)
    rescue Serp::Error
      nil
    end

    private

    def adapter
      Serp.adapter_class(run.provider).new
    end
  end
end
