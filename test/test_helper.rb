# Shared setup for all tests. Load it at the top of every test file.
require "minitest/autorun"

# log and describe_openai_error normally come from cakee.rb.
# In tests, log lines are collected in LOGS so tests can check them.
LOGS = []
def log(message) = LOGS << message
def describe_openai_error(_error) = "fake error"
