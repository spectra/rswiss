# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 43):
# <pablo@propus.com.br> wrote this file and it's provided AS-IS, no
# warranties. As long as you retain this notice you can do whatever you
# want with this stuff. If we meet some day, and you think this stuff is
# worth it, you can buy me a beer in return."
# ----------------------------------------------------------------------
require 'xml-rswiss'
require 'rack-xmlrpc'

s = Rack::XMLRPCServer.new
s.add_introspection
s.add_handler("matchmaker", XMLRSwiss.new)

run s
