# frozen_string_literal: true

module AhoyDashboard
  module Seo
    class ReturnLinkPresenter
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
        uri = Referer.local_uri(referer, host: host)
        return if uri.nil? || uri.path == path

        surface = Surface::ALL.find { |candidate| candidate.path == uri.path }
        @memory = ({ "page" => path, "key" => surface.key, "url" => Referer.full_path(uri) } if surface)
      end

      def remembered_surface
        return unless memory && memory["page"] == path

        Surface::ALL.find { |candidate| candidate.key == memory["key"] }
      end
    end
  end
end
