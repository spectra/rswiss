require 'rswiss.rb'
require 'pp'
players = ARGV[0].to_i
repeat_on = (ARGV.length > 1)
tournament = 0
problems = 0
workarounds = 0
while true
	p = [];0.upto(players) { |n| p << n }
	t = Tournament.new(p, repeat_on)
	puts "\nNew tournment: #{tournament}. Repeating matches as last resort is <#{repeat_on ? "" : "not "}allowed>. Now is #{Time.now}."
	while true
		not_ended = false
		begin
			m = t.get_next_match
		rescue RuntimeError
			# Some error like end of tournament
			break
		rescue StandardError
			# Fatal error
			not_ended = true
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
		t.put_match(m)
	end
	
	if ! not_ended
		pp t.final_chart if players < 50
		begin
			winner = t.winner
			puts "The winner (by #{winner[1]}) is:"
			pp winner[0]
			workarounds += t.repeated_matches
		rescue RuntimeError
			puts "This have to be decided by luck..."
		end
	else
		puts "Something bad happened"
		problems += 1
	end
	tournament += 1
	puts ">>>> Problem rate: #{problems}/#{tournament} / Repeated matches: #{workarounds}"
	sleep 1
end

# vim: set ts=2:
