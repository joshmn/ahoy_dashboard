require File.expand_path("lib/ahoy_dashboard/version", __dir__)

Gem::Specification.new do |spec|
  spec.name        = "ahoy_dashboard"
  spec.version     = AhoyDashboard::VERSION
  spec.authors     = [ "Josh" ]
  spec.summary     = "A self-hosted analytics dashboard for ahoy_matey."
  spec.description = "Reads the ahoy tables and renders a dashboard. Spiritual successor to ahoy_captain."
  spec.homepage    = "https://github.com/joshmn/ahoy_dashboard"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 2.5"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # chdir, because Dir globs the working directory and this gemspec gets loaded
  # from the host application's root as often as from its own.
  spec.files = Dir.chdir(__dir__) do
    Dir["{app,assets,config,db,docs,lib}/**/*"].select { |path| File.file?(path) } +
      [ "MIT-LICENSE", "README.md" ]
  end

  spec.add_dependency "rails", ">= 6.0"
  spec.add_dependency "csv", ">= 3.0"

  # Only the build_css task needs these, and only when working on the gem: the
  # compiled stylesheet is committed.
  spec.add_development_dependency "bootstrap", "~> 5.3"
  spec.add_development_dependency "sass-embedded"
end
