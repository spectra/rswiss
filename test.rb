# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 43):
# <pablo@propus.com.br> wrote this file and it's provided AS-IS, no
# warranties. As long as you retain this notice you can do whatever you
# want with this stuff. If we meet some day, and you think this stuff is
# worth it, you can buy me a beer in return."
# ----------------------------------------------------------------------
require 'rswiss.rb'
require 'pp'
players = ARGV[0].to_i
repeat_on = (ARGV.length > 1)
marshal_test = true
tournament = 0
problems = 0
workarounds = 0
while true
	p = [];0.upto(players) { |n| p << n }
	t = RSwiss::Tournament.new(p, repeat_on)
	puts "\nNew tournment: #{tournament}. Repeating matches as last resort is <#{repeat_on ? "" : "not "}allowed>. Now is #{Time.now}."
	while true
		not_ended = false
		message = ""
		begin
			m = t.checkout_match
		rescue RSwiss::EndOfTournament
			# Some error like end of tournament
			break
		rescue RSwiss::MaxRearranges, RSwiss::RepetitionExhausted, RSwiss::UnknownAlgorithm => e
			# Fatal error
			not_ended = true
			message = e.message
			break
		end
		rnd = rand(100)
		if rnd < 20
			# 20% chance of draw
			m.decide(0)
		elsif rnd >= 20 and rnd < 70
			# 50% chance of the highest score win
			if m.p1.score > m.p2.score
				m.decide(1)
			else
				m.decide(2)
			end
		else
			# 30% chance of the lowest score win
			if m.p1.score > m.p2.score
				m.decide(2)
			else
				m.decide(1)
			end
		end
#		t.commit_match([m.p1.id, m.p2.id, m.result])
		t.commit_match(m)
		if marshal_test
			puts ">>> Marshal test going on..."
			s = Marshal.dump(t)
			t = Marshal.load(s)
		end
	end
	
	if ! not_ended
		pp t.table_by_criteria if players < 50
#		pp t.table2array(t.table_by_criteria) if players < 50
		begin
			winner = t.winner
			puts "The winner (by #{winner[1]}) is:"
			pp winner[0]
			workarounds += t.repeated_matches
		rescue RSwiss::StillTied
			puts "This have to be decided by luck..."
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
