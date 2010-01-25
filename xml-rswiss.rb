require 'rswiss'
require 'xmlrpc/server'

class XMLRSwiss

	def initialize
		@tournaments = []
		@mutex = Mutex.new
	end

	def dispatcher(method, *args, &block)
		retval = nil
		begin
			case method
				when :create_tournament then
					players = args[0]
					repeat_on = args[1]
					@mutex.synchronize {
						@tournaments << RSwiss::Tournament.new(players, repeat_on)
						retval = (@tournaments.length - 1)
					}
				when :checkout_match then
					tournament_id = args[0]
					match = @tournaments[tournament_id].checkout_match
					retval = [ match.p1.id, match.p2.id ]
				when :commit_match then
					tournament_id = args[0]
					match_arr = args[1]
					match_arr << args[2]
					match = RSwiss::Match.new(match_arr)
					@tournaments[tournament_id].commit_match(match)
					retval = true
				when :has_ended then
					tournament_id = args[0]
					retval = @tournaments[tournament_id].ended?
				when :table_by_score then
					tournament_id = args[0]
					table = @tournaments[tournament_id].table_by_score
					retval = @tournaments[tournament_id].table2array(table)
				when :table_by_criteria then
					tournament_id = args[0]
					table = @tournaments[tournament_id].table_by_criteria
					retval = @tournaments[tournament_id].table2array(table)
				when :winner then
					tournament_id = args[0]
					winner = @tournaments[tournament_id].winner
					retval = [ winner[0].id, winner[1].to_s ]
			end
		rescue RSwiss::RepeatedPlayersIds => e
			# Raised from Tournament.new
			raise XMLRPC::FaultException.new(101, e.message)
		rescue RuntimeError => e
			# Raised from #gen_next_round (from #checkout_match)
			raise XMLRPC::FaultException.new(201, e.message)
		rescue RSwiss::EndOfTournament => e
			# Raised from #gen_next_round (from #checkout_match) or from #commit_match
			raise XMLRPC::FaultException.new(202, e.message)
		rescue ArgumentError => e
			# Raised from #commit_match
			raise XMLRPC::FaultException.new(301, e.message)
		rescue RSwiss::MatchExists => e
			# Raised from #commit_match
			raise XMLRPC::FaultException.new(302, e.message)
		rescue RSwiss::MatchNotCheckedOut => e
			# Raised from #commit_match
			raise XMLRPC::FaultException.new(303, e.message)
		rescue RSwiss::StillRunning => e
			# Raised from #winner
			raise XMLRPC::FaultException.new(401, e.message)
		rescue RSwiss::StillTied => e
			# Raised from #winner
			raise XMLRPC::FaultException.new(402, e.message)
		end
		return retval
	end
	private :dispatcher

	def create_tournament(players, repeat_on = true)
		dispatcher(:create_tournament, players, repeat_on)
	end

	def checkout_match(tournament_id)
		dispatcher(:checkout_match, tournament_id)
	end

	def commit_match(tournament_id, match_arr, result)
		dispatcher(:commit_match, tournament_id, match_arr, result)
	end

	def has_ended(tournament_id)
		dispatcher(:has_ended, tournament_id)
	end

	def table_by_score(tournament_id)
		dispatcher(:table_by_score, tournament_id)
	end

	def table_by_criteria(tournament_id)
		dispatcher(:table_by_criteria, tournament_id)
	end

	def winner(tournament_id)
		dispatcher(:winner, tournament_id)
	end

end # of class XMLRSwiss

s = XMLRPC::Server.new(9090)
s.add_introspection
s.add_handler("matchmaker", XMLRSwiss.new)
s.serve
