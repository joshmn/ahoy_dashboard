# Tasks for working on the gem itself. Deliberately not in lib/tasks: the engine
# loads that directory into every host application, and a host has no reason to
# own a build, no reason to have node or the bootstrap gem, and no way to run
# any of this. Everything under assets/builds is committed; consumers build
# nothing.

require "pathname"
require "json"
require "openssl"
require File.expand_path("lib/ahoy_dashboard/asset_manifest", __dir__)

ROOT = Pathname(__dir__)
BUILDS = ROOT.join("assets/builds")
ESBUILD_VERSION = "0.28.2".freeze
BOOTSTRAP_VERSION = "5.3.8".freeze
SASS_VERSION = "1.105.1".freeze

task default: :build

desc "compile the stylesheet and the script into assets/builds"
task build: [ :build_css, :build_js ]

desc "compile assets/stylesheets into assets/builds/ahoy_dashboard.css"
task :build_css do
  begin
    require "sass-embedded"
  rescue LoadError
    abort "needs the sass-embedded gem: gem install sass-embedded"
  end

  bootstrap = begin
    Gem::Specification.find_by_name("bootstrap").gem_dir
  rescue Gem::MissingSpecError
    abort "needs the bootstrap gem for its sass: gem install bootstrap -v '~> 5.3'"
  end

  abort "build requires bootstrap #{BOOTSTRAP_VERSION}" unless Gem.loaded_specs.fetch("bootstrap").version.to_s == BOOTSTRAP_VERSION
  abort "build requires sass-embedded #{SASS_VERSION}" unless Gem.loaded_specs.fetch("sass-embedded").version.to_s == SASS_VERSION

  result = Sass.compile(
    ROOT.join("assets/stylesheets/ahoy_dashboard.scss").to_s,
    load_paths: [ ROOT.join("assets/stylesheets").to_s, File.join(bootstrap, "assets/stylesheets") ],
    style: :compressed,
    silence_deprecations: [ "import", "global-builtin", "color-functions", "mixed-decls" ]
  )

  BUILDS.mkpath
  BUILDS.join("ahoy_dashboard.css").write(result.css)
  AhoyDashboard::AssetManifest.new(root: ROOT).record(
    kind: "stylesheet", compiler: "sass-embedded #{SASS_VERSION}, bootstrap #{BOOTSTRAP_VERSION}"
  )
  puts "wrote assets/builds/ahoy_dashboard.css, #{result.css.bytesize} bytes"
end

desc "bundle assets/javascript into assets/builds/ahoy_dashboard.js"
task :build_js do
  # The module tree is 24 files that import each other, and every request for
  # one goes through the dashboard's own controller and its authorization. A
  # cold load was 24 authenticated round trips three imports deep. One file is
  # one round trip.
  entry = ROOT.join("assets/javascript/index.js")
  out = BUILDS.join("ahoy_dashboard.js")
  BUILDS.mkpath

  command = [
    "npx", "--yes", "esbuild@#{ESBUILD_VERSION}", entry.to_s,
    "--bundle", "--format=esm", "--minify", "--sourcemap",
    "--target=es2022", "--charset=utf8",
    "--outfile=#{out}"
  ]

  abort "needs node, for esbuild" if `command -v npx`.strip.empty?
  abort "esbuild failed" unless system(*command)

  AhoyDashboard::AssetManifest.new(root: ROOT).record(kind: "javascript", compiler: "esbuild #{ESBUILD_VERSION}")

  puts "wrote assets/builds/ahoy_dashboard.js, #{out.size} bytes"
end


desc "test the dashboard JavaScript without browser dependencies"
task :test_javascript do
  files = ROOT.glob("spec/javascript/*_test.mjs").map(&:to_s)
  abort "JavaScript tests failed" unless system("node", "--experimental-default-type=module", "--test", *files)
end
