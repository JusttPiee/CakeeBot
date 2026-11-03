require_relative "test_helper"
require_relative "../time_ago"

class TimeAgoTest < Minitest::Test
  NOW = Time.new(2026, 11, 3, 12, 0, 0)

  def ago(seconds) = time_ago(NOW - seconds, NOW)

  def test_under_a_minute_is_just_now
    assert_equal "just now", ago(30)
  end

  def test_minutes
    assert_equal "1 minute ago", ago(60)
    assert_equal "5 minutes ago", ago(5 * 60)
  end

  def test_hours
    assert_equal "1 hour ago", ago(3600)
    assert_equal "3 hours ago", ago(3 * 3600 + 120)
  end

  def test_days
    assert_equal "1 day ago", ago(24 * 3600)
    assert_equal "3 days ago", ago(3 * 24 * 3600)
  end
end
