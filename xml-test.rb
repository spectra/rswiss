# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 43):
# <pablo@propus.com.br> wrote this file and it's provided AS-IS, no
# warranties. As long as you retain this notice you can do whatever you
# want with this stuff. If we meet some day, and you think this stuff is
# worth it, you can buy me a beer in return."
# ----------------------------------------------------------------------
require 'xmlrpc/client'
require 'pp'
players = ARGV[0].to_i
repeat_on = (ARGV.length > 1)
tournament = 0
problems = 0
workarounds = 0
while true
	p = [];0.upto(players) { |n| p << n }
	client = XMLRPC::Client.new2("http://localhost:9090/")
	t_id = client.call("matchmaker.create_tournament", p, 0, repeat_on)
	puts "\nNew tournment: #{tournament} (id = #{t_id}). Repeating matches as last resort is <#{repeat_on ? "" : "not "}allowed>. Now is #{Time.now}."
	while true
		not_ended = false
		message = ""
		begin
			m_arr = client.call("matchmaker.checkout_match", t_id)
		rescue XMLRPC::FaultException => e
			if e.faultCode != 202
				not_ended = true
				message = e.message
			end
			break
		end
		rnd = rand(100)
		result = nil
		if rnd < 20
			# 20% chance of draw
			result = 0
		elsif rnd >= 20 and rnd < 70
			# 50% chance of p1 win
			result = 1
		else
			# 30% chance of p2 win
			result = 2
		end
		client.call("matchmaker.commit_match", t_id, m_arr, result)
	end
	
	if ! not_ended
		pp client.call("matchmaker.table_by_criteria", t_id) if players < 50
		begin
			winner = client.call("matchmaker.winner", t_id)
			puts "The winner (by #{winner[1]}) is:"
			pp winner[0]
			workarounds += client.call("matchmaker.repeated_matches", t_id)
		rescue XMLRPC::FaultException => e
			puts "This have to be decided by luck..." if e.faultCode == 402
		end
	else
		puts "Something bad happened: #{message}"
		problems += 1
	end
	tournament += 1
	puts ">>>> Problem rate: #{problems}/#{tournament} / Repeated matches: #{workarounds}"
	sleep 1
end

# vim: set ts=2:
