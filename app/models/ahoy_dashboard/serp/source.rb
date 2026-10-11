module AhoyDashboard
  module Serp
    Source = Data.define(:index, :link, :domain, :title) do
      def initialize(index:, link:, domain: nil, title: nil)
        super(index: index.to_i, link: link, domain: domain || Domain.host(link), title: title.presence)
      end
    end
  end
end
