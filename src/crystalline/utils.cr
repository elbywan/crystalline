module Crystalline
  private module Async(T)
    def self.spawn_on_different_thread(thread : Thread, &block : ->) : Nil
      block
      {% if flag?(:preview_mt) %}
        spawn same_thread: false do
          if Thread.current == thread
            spawn_on_different_thread(thread, &block)
          else
            block.call
          end
        end
      {% else %}
        spawn(&block)
      {% end %}
    end

    def self.await(&block : -> T) : T
      channel = Channel(T | Exception).new
      spawn do
        channel.send block.call
      rescue e : Exception
        e
      end
      result = channel.receive
      raise result if result.is_a? Exception
      result
    end

    def self.lock(lock : Mutex, &block : ->) : Nil
      spawn do
        lock.synchronize {
          block.call
        }
      end
    end
  end
end
