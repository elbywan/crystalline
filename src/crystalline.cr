require "./crystalline/requires"
require "./crystalline/*"
require "option_parser"

log_level = ::Log::Severity::Warn

OptionParser.parse do |parser|
  parser.banner = "Usage: crystalline [options]"

  parser.on("-v", "--version", "Show version") do
    puts Crystalline::VERSION
    exit
  end

  parser.on("-h", "--help", "Show help") do
    puts parser
    exit
  end

  parser.on("-l LEVEL", "--log LEVEL", "Set log level (debug, info, warn, error). Default: warn") do |level|
    log_level = case level.downcase
                when "debug" then ::Log::Severity::Debug
                when "info"  then ::Log::Severity::Info
                when "warn"  then ::Log::Severity::Warn
                when "error" then ::Log::Severity::Error
                else
                  STDERR.puts "Invalid log level: #{level}"
                  exit 1
                end
  end

  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit 1
  end
end

Crystalline.init(log_level: log_level)
