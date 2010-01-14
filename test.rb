require 'rswiss.rb'
require 'pp'
players = ARGV[0].to_i
p = [];0.upto(players) { |n| p << Player.new(n) }
t = Tournament.new; p.each { |pl| t.add_player(pl) }
t.begin!
t.rounds.times do |round|
	puts "Round #{round}"
	while true
		begin
			m = t.get_next_match
		rescue RuntimeError
			break
		end
		puts ">>> Match p1=#{m.p1.id}/#{m.p1.score} p2=#{m.p2.id}/#{m.p2.score}"
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
end

pp t.final_chart

if t.is_tied?
	puts "We have a tie. After the tie break, the winner is:"
	pp t.tie_break
else
	puts "The winner is:"
	pp t.winner
end

# vim: set ts=2:
