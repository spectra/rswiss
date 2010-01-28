require 'rswiss'
require 'xmlrpc/server'
require 'pstore'

class XMLRSwiss

	def initialize(file = nil)
		@file = file.nil? ? "/tmp/XMLRSwiss.#{$$}.pstore" : file
		@pstore = PStore.new(@file)
		@pstore.transaction {
			@pstore[:tournaments] ||= Array.new
		}
	end

	def dispatcher(method, *args, &block)
		retval = nil
		begin
			case method
				when :create_tournament then
					players = args[0]
					repeat_on = args[1]
					@pstore.transaction {
						@pstore[:tournaments] << RSwiss::Tournament.new(players, repeat_on)
						retval = (@pstore[:tournaments].length - 1)
					}
				when :checkout_match then
					tournament_id = args[0]
					@pstore.transaction {
						match = @pstore[:tournaments][tournament_id].checkout_match
						retval = [ match.p1.id, match.p2.id ]
					}
				when :commit_match then
					tournament_id = args[0]
					match_arr = args[1]
					match_arr << args[2]
					@pstore.transaction {
						@pstore[:tournaments][tournament_id].commit_match(match_arr)
					}
					retval = true
				when :has_ended then
					tournament_id = args[0]
					@pstore.transactio(true) {
						retval = @pstore[:tournaments][tournament_id].ended?
					}
				when :table_by_score then
					tournament_id = args[0]
					@pstore.transaction(true) {
						table = @pstore[:tournaments][tournament_id].table_by_score
						retval = @pstore[:tournaments][tournament_id].table2array(table)
					}
				when :table_by_criteria then
					tournament_id = args[0]
					@pstore.transaction(true) {
						table = @pstore[:tournaments][tournament_id].table_by_criteria
						retval = @pstore[:tournaments][tournament_id].table2array(table)
					}
				when :winner then
					tournament_id = args[0]
					@pstore.transaction(true) {
						winner = @pstore[:tournaments][tournament_id].winner
						retval = [ winner[0].id, winner[1].to_s ]
						puts ">>>>>"
						puts @pstore[:tournaments]
					}
				when :repeated_matches then
					tournament_id = args[0]
					@pstore.transaction(true) {
						retval = @pstore[:tournaments][tournament_id].repeated_matches
					}
				when :checkedout_matches then
					tournament_id = args[0]
					retval = []
					@pstore.transaction(true) {
						@pstore[:tournaments][tournament_id].checkedout_matches.each do |match|
							retval << [match.p1, match.p2]
						end
					}
			end
		rescue RSwiss::RepeatedPlayersIds => e
			# Raised from Tournament.new
			raise XMLRPC::FaultException.new(101, e.message)
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
		rescue RuntimeError => e
			# Raised from #gen_next_round (from #checkout_match)
			raise XMLRPC::FaultException.new(201, e.message)
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

	def checkedout_matches(tournament_id)
		dispatcher(:checkedout_matches, tournament_id)
	end

	def repeated_matches(tournament_id)
		dispatcher(:repeated_matches, tournament_id)
	end

end # of class XMLRSwiss

s = XMLRPC::Server.new(9090)
s.add_introspection
s.add_handler("matchmaker", XMLRSwiss.new(ARGV[0]))
s.serve
