require 'rswiss.rb'
require 'pp'
players = ARGV[0].to_i
tournament = 0
problems = 0
while true
	p = [];0.upto(players) { |n| p << Player.new(n) }
	t = Tournament.new; p.each { |pl| t.add_player(pl) }
	t.begin!
	puts "\nNew tournment: #{tournament}. Now is #{Time.now}."
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
		winner = t.winner
		puts "The winner (by #{winner[1]}) is:"
		pp winner[0]
	else
		puts "Something bad happened"
		problems += 1
	end
	tournament += 1
	puts ">>>> Problem rate: #{problems}/#{tournament}"
	sleep 1
end

# vim: set ts=2:
