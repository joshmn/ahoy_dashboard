module AhoyDashboard
  module Assets
    class UnknownAsset < StandardError; end

    STYLESHEET = "ahoy_dashboard.css".freeze
    SCRIPT = "ahoy_dashboard.js".freeze
    SOURCEMAP = "ahoy_dashboard.js.map".freeze

    BUILT = [ STYLESHEET, SCRIPT, SOURCEMAP ].freeze

    FONT = %r{\Afonts/[a-z0-9][a-z0-9_\-.]*\.woff2\z}i

    TYPES = {
      ".css" => "text/css",
      ".js" => "text/javascript",
      ".map" => "application/json",
      ".woff2" => "font/woff2"
    }.freeze

    class << self
      def root
        @root ||= Pathname(AhoyDashboard.config.assets_root.presence ||
          AhoyDashboard::Engine.root.join("assets"))
      end

      def builds
        root.join("builds")
      end

      def fonts
        root.join("fonts")
      end

      def build
        return compute_build if reload?

        @build ||= compute_build
      end

      def resolve(path)
        raise UnknownAsset, path unless path.is_a?(String)

        if BUILT.include?(path)
          found(builds.join(path), path)
        elsif path.match?(FONT)
          found(fonts.join(File.basename(path)), path)
        else
          raise UnknownAsset, path
        end
      end

      def content_type(file)
        TYPES.fetch(File.extname(file.to_s), "application/octet-stream")
      end

      def files
        [ *BUILT.map { |name| builds.join(name) }, *fonts.glob("*.woff2") ].select(&:file?).sort
      end

      private

      def found(file, path)
        raise UnknownAsset, path unless file.file?

        file
      end

      def compute_build
        digest = OpenSSL::Digest::SHA256.new

        files.each do |file|
          digest << file.relative_path_from(root).to_s
          digest << File.binread(file)
        end

        digest.hexdigest.first(16)
      end

      def reload?
        !Rails.application.config.eager_load
      end
    end
  end
end
