# encoding: UTF-8

require 'date'
require 'digest'

intervalo = 2
codigo = "6745231"
date = DateTime.now() + (intervalo.to_f / 24)
date_s = date.strftime("%Y%m%d")
puts Digest::MD5.hexdigest "#{codigo}#{date_s}"
