require_relative "test_helper"
require_relative "../channel_lock"

class ChannelLockTest < Minitest::Test
  def test_returns_the_block_result
    assert_equal 42, with_channel_lock(1) { 42 }
  end

  def test_same_channel_runs_one_at_a_time
    order = []
    threads = 2.times.map do |i|
      Thread.new do
        with_channel_lock(100) do
          order << "start #{i}"
          sleep 0.05 # pretend to wait for OpenAI
          order << "end #{i}"
        end
      end
    end
    threads.each(&:join)

    # Each message must finish before the next one starts: start, end, start, end
    assert_equal ["start", "end", "start", "end"], order.map { |step| step.split.first }
  end

  def test_different_channels_do_not_wait_for_each_other
    started = Queue.new
    slow = Thread.new { with_channel_lock(200) { started << true; sleep 0.3 } }
    started.pop # wait until channel 200 is holding its lock

    elapsed = measure { with_channel_lock(201) { :done } }
    slow.join
    assert elapsed < 0.1, "channel 201 waited #{elapsed}s for channel 200"
  end

  def measure
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  end
end
