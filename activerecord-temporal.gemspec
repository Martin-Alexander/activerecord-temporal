Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY
  s.name = "activerecord-temporal"
  s.version = "0.3.0"
  s.summary = "Time-travel querying, application/system versioning, and bitemporal support for Active Record"
  s.description = "An unobtrusive and modular plugin for Active Record that adds support for time-travel querying and data versioning at the application level, at the system level via PostgreSQL triggers, or both."

  s.required_ruby_version = ">= 3.2.0"

  s.license = "MIT"

  s.authors = ["Martin-Alexander"]
  s.homepage = "https://github.com/Martin-Alexander/activerecord-temporal"
  s.email = ["martingianna@gmail.com"]

  s.files = Dir["CHANGELOG.md", "LICENSE.txt", "README.md", "lib/**/*"]
  s.require_path = "lib"

  s.metadata = {
    "bug_tracker_uri" => "https://github.com/Martin-Alexander/activerecord-temporal/issues",
    "changelog_uri" => "https://github.com/Martin-Alexander/activerecord-temporal/blob/master/CHANGELOG.md",
    "homepage_uri" => s.homepage,
    "source_code_uri" => "https://github.com/Martin-Alexander/activerecord-temporal"
  }

  s.add_dependency "activerecord", ">= 8", "< 9.0"
  s.add_dependency "activesupport", ">= 8", "< 9.0"
  s.add_dependency "pg", ">= 1.0"
end
