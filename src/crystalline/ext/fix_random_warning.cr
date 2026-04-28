# This file fixes a deprecation warning in Crystal 1.20.0 stdlib
# when preview_mt is NOT enabled.
# See: /usr/share/crystal/src/kernel.cr:580

{% if !flag?(:preview_mt) && flag?(:unix) %}
  class Process
    # :nodoc:
    def self.after_fork_child_callbacks
      @@after_fork_child_callbacks ||= [
        # reinit event loop first:
        -> { Crystal::EventLoop.current.after_fork },

        # reinit signal handling:
        ->Crystal::System::Signal.after_fork,
        ->Crystal::System::SignalChildHandler.after_fork,

        # additional reinitialization
        -> { Random.new.new_seed },
        -> { Random.thread_default.new_seed },
      ] of -> Nil
    end
  end
{% end %}
