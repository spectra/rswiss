# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 43):
# <pablo@propus.com.br> wrote this file and it's provided AS-IS, no
# warranties. As long as you retain this notice you can do whatever you
# want with this stuff. If we meet some day, and you think this stuff is
# worth it, you can buy me a beer in return."
# ----------------------------------------------------------------------
require 'data/init'
require 'pp'
players = ARGV[0].to_i
repeat_on = (ARGV.length > 1)
tournament = 0
problems = 0
workarounds = 0
while true
	p = [];0.upto(players) { |n| p << n }
	t = RSwiss::Tournament.create(:n_players => p.length)
	t.allow_repeat = repeat_on
	t.inject_players(p)
	t.save
	puts "\nNew tournment: #{tournament} id=#{t.id}. Repeating matches as last resort is <#{repeat_on ? "" : "not "}allowed>. Now is #{Time.now}."
	while true
		not_ended = false
		message = ""
		begin
			puts ">>> Checking out: #{Time.now}"
			m = t.checkout_match
			puts ">>> Checked out: #{Time.now}"
		rescue RSwiss::EndOfTournament
			# Some error like end of tournament
			break
		rescue RSwiss::MaxRearranges, RSwiss::RepetitionExhausted, RSwiss::UnknownAlgorithm => e
			# Fatal error
			not_ended = true
			message = e.message
			break
		end
		m.result = rand(3) - 1
		puts ">>> Committing"
		t.commit_match(m)
		puts ">>> Committed"
	end
	
	if ! not_ended
		pp t.players(:criteria) if players < 50
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
