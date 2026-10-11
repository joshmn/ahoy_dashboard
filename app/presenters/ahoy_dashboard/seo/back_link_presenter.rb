# frozen_string_literal: true

module AhoyDashboard

  module Seo

    class BackLinkPresenter
      attr_reader :label, :url, :key, :memory

      def initialize(host:, path:, referer:, remembered:, fallback_label:, fallback_url:)
        @host = host
        @path = path
        @referer = referer
        @memory = remembered
        remember_referer
        surface = remembered_surface
        @label = "Back to #{surface ? surface.title : fallback_label}"
        @url = surface ? memory.fetch("url") : fallback_url
        @key = surface.key if surface
      end

      private

      attr_reader :host, :path, :referer

      def remember_referer
        uri = URI.parse(referer.to_s)
        return if uri.host.present? && uri.host != host
        return unless uri.path.to_s.start_with?("/")
        return if uri.path == path

        surface = Surface::ALL.find { |candidate| candidate.path == uri.path }
        @memory = if surface
          { "page" => path, "key" => surface.key, "url" => [uri.path, uri.query.presence].compact.join("?") }
        end
      rescue URI::InvalidURIError
        nil
      end

      def remembered_surface
        return unless memory && memory["page"] == path

        Surface::ALL.find { |candidate| candidate.key == memory["key"] }
      end
    end
  end
end
