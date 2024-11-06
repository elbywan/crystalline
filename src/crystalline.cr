require "./crystalline/requires"
require "./crystalline/*"

if ARGV.includes?("--version")
  puts(Crystalline::VERSION)
  exit
end

Crystalline.init
