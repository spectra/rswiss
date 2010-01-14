require 'rswiss.rb'
require 'pp'
players = ARGV[0].to_i
p = [];0.upto(players) { |n| p << Player.new(n) }
t = Tournament.new; p.each { |pl| t.add_player(pl) }
t.begin!
while true
	begin
		m = t.get_next_match
	rescue RuntimeError
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

pp t.final_chart

winner = t.winner
puts "The winner (by #{winner[1]}) is:"
pp winner[0]

# vim: set ts=2:
