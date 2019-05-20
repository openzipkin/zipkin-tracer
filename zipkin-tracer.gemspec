lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'zipkin-tracer/version'

Gem::Specification.new do |s|
  s.name        = 'zipkin-tracer'
  s.version     = ZipkinTracer::VERSION
  s.authors     = ['Franklin Hu', 'R Tyler Croy', 'James Way', 'Jordi Polo', 'Julien Feltesse', 'Scott Steeg', 'Yohei Kitamura']
  s.email       = ['franklin@twitter.com', 'tyler@monkeypox.org', 'jamescway@gmail.com', 'jcarres@medidata.com', 'jfeltesse@medidata.com', 'ssteeg@medidata.com', 'ykitamura@medidata.com']
  s.summary     = 'Ruby tracing via Zipkin'
  s.description = 'Adds tracing instrumentation for ruby applications'
  s.license     = 'Apache-2.0'
  s.metadata    = {
    'homepage_uri'  => 'https://github.com/openzipkin/zipkin-ruby',
    'changelog_uri' => 'https://github.com/openzipkin/zipkin-ruby/blob/master/CHANGELOG.md'
  }

  s.required_ruby_version = '>= 2.3.0'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  s.files = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  s.require_paths = ['lib']

  s.add_dependency 'faraday', '~> 0.8'
  s.add_dependency 'rack', '>= 1.6'
  s.add_dependency 'sucker_punch', '~> 2.0'

  s.add_development_dependency 'aws-sdk-sqs', '~> 1.0'
  s.add_development_dependency 'excon', '~> 0.53'
  s.add_development_dependency 'rspec', '~> 3.8'
  s.add_development_dependency 'rack-test', '~> 1.1'
  s.add_development_dependency 'rake', '~> 10.0'
  s.add_development_dependency 'timecop', '~> 0.8'
  s.add_development_dependency 'webmock', '~> 3.0'
  s.add_development_dependency 'simplecov', '~> 0.16'
end
