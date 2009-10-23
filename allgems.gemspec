spec = Gem::Specification.new do |s|
    s.name              = 'allgems'
    s.author            = %q(spox)
    s.email             = %q(spox@modspox.com)
    s.version           = '0.1.0'
    s.summary           = %q(Tools to document the world)
    s.platform          = Gem::Platform::RUBY
    s.files             = Dir['**/*']
    s.rdoc_options      = %w(--title AllGems --main README.rdoc --line-numbers)
    s.extra_rdoc_files  = %w(README.rdoc CHANGELOG)
    s.require_paths     = %w(lib)
    s.executables       = %w(allgems)
    s.required_ruby_version = '>= 1.8.6'
    s.homepage          = %q(http://github.com/spox/allgems)
    s.description       = 'AllGems is a tool to provide comprehensive gem documentation for an entire index'
end
