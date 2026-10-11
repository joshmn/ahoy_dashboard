# frozen_string_literal: true

module AhoyDashboard

  class AssetManifest
    INPUTS = {
      "javascript" => "assets/javascript/**/*.js",
      "stylesheet" => "assets/stylesheets/**/*.scss"
    }.freeze
    OUTPUTS = {
      "javascript" => %w[ahoy_dashboard.js ahoy_dashboard.js.map],
      "stylesheet" => %w[ahoy_dashboard.css]
    }.freeze

    def initialize(root:)
      @root = Pathname(root)
    end

    def record(kind:, compiler:)
      manifest = path.file? ? JSON.parse(path.read) : {}
      manifest[kind] = { "compiler" => compiler, "inputs" => inputs(kind), "outputs" => outputs(kind) }
      path.write(JSON.pretty_generate(manifest) + "\n")
    end

    def current?(kind:)
      return false unless path.file?

      stored = JSON.parse(path.read).fetch(kind, {})
      stored["inputs"] == inputs(kind) && stored["outputs"] == outputs(kind)
    end

    private

    attr_reader :root

    def path
      root.join("assets/builds/manifest.json")
    end

    def inputs(kind)
      fingerprints(root.glob(INPUTS.fetch(kind)) + [root.join("Rakefile")])
    end

    def outputs(kind)
      fingerprints(OUTPUTS.fetch(kind).map { |name| root.join("assets/builds", name) })
    end

    def fingerprints(files)
      files.sort.each_with_object({}) do |file, found|
        found[file.relative_path_from(root).to_s] = OpenSSL::Digest::SHA256.file(file).hexdigest
      end
    end
  end
end
