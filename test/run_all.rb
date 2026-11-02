# Runs every *_test.rb file in this folder.
# Usage (from the project folder): bundle exec ruby test/run_all.rb
Dir[File.join(__dir__, "*_test.rb")].sort.each { |file| require file }
