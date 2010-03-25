# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 43):
# <pablo@propus.com.br> wrote this file and it's provided AS-IS, no
# warranties. As long as you retain this notice you can do whatever you
# want with this stuff. If we meet some day, and you think this stuff is
# worth it, you can buy me a beer in return."
# ----------------------------------------------------------------------
require 'xmlrpc/client'
players = ARGV[0].to_i
repeat_on = (ARGV.length > 1)
p = [];0.upto(players) { |n| p << n }
client = XMLRPC::Client.new2("http://localhost:9090/")
puts "\nCreating a new tournament"
t_id = client.call("matchmaker.create_tournament", p, 0, repeat_on)
puts "\nNew tournment: #{t_id}. Repeating matches as last resort is <#{repeat_on ? "" : "not "}allowed>. Now is #{Time.now}."

# vim: set ts=2:
