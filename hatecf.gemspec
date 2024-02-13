Gem::Specification.new do |s|
  s.name        = "hatecf"
  s.version     = "0.0.2"
  s.summary     = "Configuration management powered by hate"
  s.description = "Configuration management engine like Ansible but without YAML and 30 times faster"
  s.authors     = ["Alexander Markov"]
  s.email       = "apshertonets@gmail.com"
  s.files       = Dir["{lib,remote}/*"] + %w(bootstrap_ruby)
  s.homepage    = "https://github.com/apsheronets/hatecf"
  s.license     = "LGPL-3.0"
end
