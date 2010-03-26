# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 43):
# <pablo@propus.com.br> wrote this file and it's provided AS-IS, no
# warranties. As long as you retain this notice you can do whatever you
# want with this stuff. If we meet some day, and you think this stuff is
# worth it, you can buy me a beer in return."
# ----------------------------------------------------------------------
require 'data/init.rb'

class XMLSSwiss

	def initialize(logger)
		@logger = logger
		SSwiss::Tournament.logger = @logger
		SSwiss::Player.logger = @logger
		SSwiss::Match.logger = @logger
	end

	def dispatcher(method, *args, &block)
		retval = nil
		begin
			case method
				when :create_tournament then
					players = args[0]
					additional_rounds = args[1]
					repeat_on = args[2]
					tournament = SSwiss::Tournament.create(:n_players => players.length, :additional_rounds => additional_rounds, :allow_repeat => repeat_on)
					tournament.save
					tournament.inject_players(players)
					retval = tournament.id
				when :checkout_match then
					tournament_id = args[0]
					tournament = SSwiss::Tournament[:id => tournament_id]
					match = tournament.checkout_match
					retval = [ match.p1.in_tournament_id, match.p2.in_tournament_id ]
				when :commit_match then
					tournament_id = args[0]
					match_arr = args[1]
					result = args[2]
					tournament = SSwiss::Tournament[:id => tournament_id]
					match_arr << result
					tournament.commit_match(match_arr)
					retval = true
				when :has_ended then
					tournament_id = args[0]
					tournament = SSwiss::Tournament[:id => tournament_id]
					retval = tournament.ended?
				when :table_by_score then
					tournament_id = args[0]
					tournament = SSwiss::Tournament[:id => tournament_id]
					table = tournament.players(:score)
					retval = table2array(table, true)
				when :table_by_criteria then
					tournament_id = args[0]
					tournament = SSwiss::Tournament[:id => tournament_id]
					table = tournament.players(:criteria)
					retval = table2array(tournament, table, true)
				when :winner then
					tournament_id = args[0]
					tournament = SSwiss::Tournament[:id => tournament_id]
					winner = tournament.winner
					retval = [ winner[0].in_tournament_id, winner[1].to_s ]
				when :repeated_matches then
					tournament_id = args[0]
					tournament = SSwiss::Tournament[:id => tournament_id]
					retval = tournament.repeated_matches
				when :checkedout_matches then
					tournament_id = args[0]
					tournament = SSwiss::Tournament[:id => tournament_id]
					retval = []
					tournament.checkedout_matches.each do |match|
						retval << [match.p1.in_tournament_id, match.p2.in_tournament_id]
					end
				when :round then
					tournament_id = args[0]
					tournament = SSwiss::Tournament[:id => tournament_id]
					retval = tournament.round
			end
		rescue SSwiss::RepeatedPlayerIds, SSwiss::DiscrepantNumberOfPlayers, SSwiss::MatchesToBeCommitted, SSwiss::EndOfTournament, SSwiss::GeneratingRound, SSwiss::MaxRearranges, SSwiss::RepetitionExhausted, SSwiss::MatchNotCheckedOut, SSwiss::StillRunning, SSwiss::StillTied => e
			if e.respond_to?(:faultCode)
				raise XMLRPC::FaultException.new(e.faultCode, e.message)
			else
				raise e
			end
		end
		return retval
	end
	private :dispatcher

	def create_tournament(players, additional_rounds = 0, repeat_on = true)
		dispatcher(:create_tournament, players, additional_rounds, repeat_on)
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

	def round(tournament_id)
		dispatcher(:round, tournament_id)
	end

	# Converts a table of players in an ordered array with all the criterias
	#
	# tournament:: The SSwiss::Tournament object.
	# table:: the table
	# add_played_matches:: boolean. If true, add the number of matches that player played already as second element of the array.
	# criteria:: the list of criterias to be included (assume the default if not given)
	def table2array(tournament, table, add_played_matches = false, mycriteria = nil)
		mycriteria = tournament.criteria if mycriteria.nil?
		ret = []
		table.each do |player|
			line = []
			line << player.in_tournament_id
			line << player.matches if add_played_matches
			mycriteria.each do |func|
				line << player.send(func)
			end
			ret << line
		end
		return ret
	end

end # of class XMLSSwiss
