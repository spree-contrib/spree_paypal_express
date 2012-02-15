source 'http://rubygems.org'

gemspec

gem 'sqlite3-ruby', :require => 'sqlite3'
gem 'spree', :path => '../spree'

group :test do
  gem 'rspec-rails', '= 2.7.0'
  gem 'factory_girl_rails', '= 1.3.0'
  gem 'simplecov'
  gem 'shoulda'
  gem 'faker'
  if RUBY_VERSION < "1.9"
    gem "ruby-debug"
  else
    gem "ruby-debug19"
  end
end

group :cucumber do
  gem 'cucumber-rails'
  gem 'database_cleaner', '~> 0.5.2'
  gem 'nokogiri'
  gem 'capybara'
  gem 'faker'
  gem 'launchy'

  if RUBY_VERSION < "1.9"
    gem "ruby-debug"
  else
    gem "ruby-debug19"
  end
end
