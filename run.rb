require 'httparty'
require 'pry'

response = HTTParty.get('https://openresty.org/en/download.html')
versions = response.body
                   .scan(/openresty\-([0-9\.]+)\.([0-9]+)\.tar\.gz/)
                   .uniq

v = versions.first

puts "DEB_MAJOR #{v[0]} DEB_MINOR #{v[1]} bash ./build"
exec({ 'DEB_MAJOR' => v[0], 'DEB_MINOR' => v[1] }, 'bash ./build')
