RSpec.configure do |config|
  config.expect_with(:rspec) do |expectations|
    expectations.syntax = [:should, :expect]
  end
  config.mock_with(:rspec) do |mocks|
    mocks.syntax = [:should, :expect]
  end
  config.run_all_when_everything_filtered = true
  config.filter_run :focus
  config.order = 'random'
end

