module AhoyDashboard
  module Serp
    Organic = Data.define(:position, :page, :link, :domain, :title, :snippet) do
      def initialize(position:, link:, page: 1, domain: nil, title: nil, snippet: nil)
        super(position: position.to_i, page: page.to_i, link: link, domain: domain || Domain.host(link),
              title: title.presence, snippet: snippet.presence)
      end
    end
  end
end
