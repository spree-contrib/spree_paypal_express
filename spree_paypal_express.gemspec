Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree_paypal_express'
  s.version     = '1.2.0'
  s.summary     = 'Adds PayPal Express as a Payment Method to Spree store'
  s.homepage    = 'http://www.spreecommerce.com'
  s.author      = 'Spree Commerce'
  s.email       = 'gems@spreecommerce.com'
  s.required_ruby_version = '>= 1.8.7'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ["lib"]
  s.has_rdoc      = false

  s.add_dependency 'spree_core', '~> 2.0.0'
  s.add_dependency 'spree_backend', '~> 2.0.0'
  s.add_dependency 'spree_frontend', '~> 2.0.0'

  s.add_development_dependency 'capybara', '~> 1.1.3'
  s.add_development_dependency 'coffee-rails'
  s.add_development_dependency 'database_cleaner'
  s.add_development_dependency 'factory_girl', '~> 3.6.0'
  s.add_development_dependency 'ffaker'
  s.add_development_dependency 'rspec-rails',  '~> 2.11.0'
  s.add_development_dependency 'sass-rails'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'sqlite3'
end
