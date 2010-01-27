require 'thread'

module RSwiss

# Class to represent a Player (this is used internally by Tournament)
class Player
	attr_reader :matches, :score, :id, :c_score, :wins, :criteria

	# Initializes a new Player
	#
	# id:: id of the player
	def initialize(id)
		@id = id
		@score = 0
		@matches = 0
		@mutex = Mutex.new
		@byed = false
		@opps_lost = []
		@opps_draw = []
		@opps_won = []
		@c_score = 0
		@wins = 0
	end

	# :nodoc:
	def marshal_dump
		[ @id, @score, @matches, @byed, @opps_lost, @opps_draw, @opps_won, @c_score, @wins ]
	end

	# :nodoc:
	def marshal_load(args)
		@id, @score, @matches, @byed, @opps_lost, @opps_draw, @opps_won, @c_score, @wins = args
		@mutex = Mutex.new
	end

	# :nodoc:
	def inspect
		sprintf("#<%s:%#x @id=%d @matches=%d @byed=%s @score=%.1f @buchholz_score=%.1f @c_score=%.1f @opp_c_score=%.1f @wins=%d, @neustadtl_score=%.2f>", self.class.name, self.__id__.abs, @id, @matches, @byed.inspect, @score, buchholz_score, @c_score, opp_c_score, @wins, neustadtl_score)
	end

	# Mark a lost game
	def lost_to(opponent)
		@mutex.synchronize {
			@matches += 1
			@opps_lost << opponent
		}
	end

	# Mark a won game
	def won_over(opponent)
		@mutex.synchronize {
			@matches += 1
			@score += 1.0
			@c_score += @score
			@wins += 1
			@opps_won << opponent
		}
	end

	# Mark a draw
	def draw_against(opponent)
		@mutex.synchronize {
			@matches += 1
			@score += 0.5
			@c_score += @score
			@opps_draw << opponent
		}
	end

	# Receive a bye (raises a RuntimeError if already received one)
	def bye
		raise AlreadyByed if @byed
		@mutex.synchronize {
			@matches += 1
			@score += 1.0
			@byed = true
		}
	end

	# Have we received a bye?
	def already_byed?; @byed; end

	# Array of opponents
	def opponents
		@opps_draw + @opps_won + @opps_lost
	end

	# Calculate the Buchholz score
	def buchholz_score
		scores = []
		opponents.each do |opponent|
			scores << opponent.score
		end
		if scores.length > 9
			# Discard first and last 2 (consider just the middle)
			scores.sort!
			scores = scores[2...-2]
		elsif scores.length > 3
			# Discard first and last
			scores.sort!
			scores = scores[1...-1]
		end
		sum = scores.inject(0) { |sum, value| sum + value }
		return sum
	end

	# Calculate the Opponent's Cumulative Score
	def opp_c_score
    opponents.inject(0) { |sum, opponent| sum + opponent.score }
	end

	# Calculate the Neustadtl Score
	def neustadtl_score
		defeated_sum = @opps_won.inject(0)  { |sum, opponent| sum + opponent.score }
		draw_sum     = @opps_draw.inject(0) { |sum, opponent| sum + opponent.score }

		return defeated_sum + (draw_sum / 2)
	end

end # of class Player

# Class to represent a Match (this is used internally by Tournament)
class Match
	attr_reader :p1, :p2, :result, :initial_score

	# Initializes a new Match
	#
	# p1:: Player 1
	# p2:: Player 2
	def initialize(p1, p2)
		@p1 = p1
		@p2 = p2
		@initial_score = [ @p1.score, @p2.score ]
		@result = nil
	end

	# :nodoc:
	def marshal_dump
		[ @p1, @p2, @initial_score, @result ]
	end

	# :nodoc:
	def marshal_load(args)
		@p1, @p2, @initial_score, @result = args
	end

	# Decide the match
	#
	# outcome:: 0 for draw, 1 for p1 wins, 2 for p2 wins
	def decide(outcome)
		raise AlreadyDecided unless @result.nil?

		# Decide the match
		case outcome
			when 1 then
				@p1.won_over(@p2)
				@p2.lost_to(@p1)
			when 2 then
				@p1.lost_to(@p2)
				@p2.won_over(@p1)
			when 0 then
				@p1.draw_against(@p2)
				@p2.draw_against(@p1)
			else
				raise ArgumentError, "A match can be decided by 0, 1 or 2."
		end
		@result = outcome
	end
end # of class Match

class Tournament
	attr_reader :round, :rounds, :checkedout_matches, :matches

	# Initializes a new tournament
	#
	# players_array:: array of player ids.
	# allow_repeated_matches:: boolean defining if we allow repeating matches as last resort (default: false).
	def initialize(players_array, allow_repeated_matches = false)
		raise RepeatedPlayersIds if players_array != players_array.uniq

		# Populate our array of players
		@players = []
		players_array.each do |player_id|
			@players << Player.new(player_id)
		end

		# Internal state.
		@rounds = (Math.log(@players.length) / Math.log(2)).ceil
		@matches = (@players.length/2).floor
		@rearranges = 0
		@round = 0
		@can_repeat_matches = [ true, false ].include?(allow_repeated_matches) ? allow_repeated_matches : false
		@criteria = [ :score, :buchholz_score, :neustadtl_score, :c_score, :opp_c_score, :wins ]

		# Match Maker
		@mutex = Mutex.new
		@generated_matches = []
		@checkedout_matches = []
		@committed_matches = []
		@repeated_matches = []
	end

	# :nodoc:
	def marshal_dump
		[ @players, @rounds, @matches, @rearranges, @round, @can_repeat_matches, @criteria, @generated_matches, @checkedout_matches, @committed_matches, @repeated_matches ]
	end

	# :nodoc:
	def marshal_load(args)
		@mutex = Mutex.new
		@mutex.lock

		@players, @rounds, @matches, @rearranges, @round, @can_repeat_matches, @criteria, @generated_matches, @checkedout_matches, @committed_matches, @repeated_matches = args

		# Regenerate match arrays with our players
		[ @generated_matches, @checkedout_matches, @committed_matches ].each do |array|
			new_array = []
			array.each do |match|
				p1 = @players.detect { |player| player.id == match.p1.id }
				p2 = @players.detect { |player| player.id == match.p2.id }

				# Pass if it is the same object
				next if match.p1.object_id == p1.object_id and match.p2.object_id == p2.object_id

				# Act otherwise
				new_match = RSwiss::Match.new(p1, p2)
				new_match.decide(match.result) unless match.result.nil?
				new_array << new_match
			end
			array = new_array
		end

		# Regenerate repeated_matches array with our players
		new_array = []
		@repeated_matches.each do |pair|
			p1 = @players.detect { |player| player.id == pair[0].id }
			p2 = @players.detect { |player| player.id == pair[1].id }
			new_array << [p1, p2]
		end
		@repeated_matches = new_array

		@mutex.unlock
	end


	# Get the number of repeated matches
	def repeated_matches
		@repeated_matches.length / 2
	end

	# Test if a match have occurred in this tournament. The order doesn't matter
	# (Player A versus Player B) == (Player B versus Player A)
	#
	# p1:: Player 1
	# p2:: Player 2
	def has_match?(p1, p2)
		! (@committed_matches.detect { |match| ((match.p1.id == p1.id and match.p2.id == p2.id) or (match.p2.id == p1.id and match.p1.id == p2.id)) }).nil?
	end

	# Test if we already have this player.
	#
	# id:: Player's id
	def has_player?(id)
		! (@players.detect { |player| player.id == id }).nil?
	end

	# Have we reached the end of the tournament?
	def ended?
		@round >= @rounds and @checkedout_matches.empty? and @generated_matches.empty?
	end

	# Checkout the next match of the tournament
	def checkout_match
		if @generated_matches.empty?
			gen_next_round
			checkout_match
		else
			match = nil
			@mutex.synchronize {
				match = @generated_matches.pop
				@checkedout_matches.push match
			}
			return match
		end
	end

	# Commit a checked-out match back in
	#
	# match_or_array:: a Match (can be an array in the form [p1_id, p2_id, result]
	def commit_match(match_or_array)
		if match_or_array.kind_of?(Array)
			match = get_match_by_p1_and_p2(@checkedout_matches, match_or_array[0], match_or_array[1])
			raise MatchNotCheckedOut if match.nil?
			if match.result.nil?
				match.decide(match_or_array[2])
			else
				raise ArgumentError, "Two different results for the same match!" if match.result != match_or_array[2]
			end
		else
			match = match_or_array
			raise ArgumentError, "This match doesn't have a result yet!" if match.result.nil?
		end
		raise MatchExists if has_match?(match.p1, match.p2) and ! @can_repeat_matches
		raise EndOfTournament if ended?

		@mutex.synchronize { 
			@committed_matches << match
			@checkedout_matches.delete(match)
		}
	end

	# Return an array of the players sorted by criteria 
	def table_by_criteria(criteria = nil)
		criteria = @criteria if criteria.nil?

		@players.sort do |a, b|
			a_side = []
			b_side = []
			criteria.each do |func|
				a_side << a.send(func)
				b_side << b.send(func)
			end
			b_side <=> a_side
		end
	end

	# Return an array of the players sorted by score
	def table_by_score
		@players.sort { |a, b| b.score <=> a.score }
	end

	# Who is the winner?
	#
	# The winner is decided using some tie-breaking criteria if needed:
	#
	# An array is returned with the winner and the criteria used.
	# An Exception is raised if the tie is too hard to break.
	def winner(criteria = nil)
		raise StillRunning unless ended?
		criteria = @criteria if criteria.nil?

		top_players = @players
		while ! criteria.empty?
			this_time_criteria = criteria.shift
			scores = []
			top_players.each do |player|
				scores << player.send(this_time_criteria)
			end
			top_players.reject! { |player| player.send(this_time_criteria) < scores.max }
			if top_players.length == 1
				# Great! We have a winner!
				return [ top_players[0], this_time_criteria ]
			end
		end

		# If got here, we have no winner
		raise StillTied
	end

	# Converts a table of players in an ordered array with all the criterias
	#
	# table:: the table
	# criteria:: the list of criterias to be included (assume the default if not given)
	def table2array(table, criteria = nil)
		criteria = @criteria if criteria.nil?
		ret = []
		table.each do |player|
			line = []
			line << player.id
			criteria.each do |func|
				line << player.send(func)
			end
			ret << line
		end
		return ret
	end

	private

	# Generate the next round of matches
	def gen_next_round
		raise RuntimeError, "Still #{@checkedout_matches.length} matches to be returned." unless @checkedout_matches.empty?
		raise EndOfTournament if ended?

		@mutex.synchronize {
			this_round = []
			@round == 0 ? @players.shuffle! : soft_rearrange! # round 0 is random

			# Will we have a last unpaired player?
			if @players.length.odd?
				# Yes :-) Let's find someone to bye!
				@players.reverse.each do |player|
					# Stop looking for if we found it.
					(player.bye; break) unless player.already_byed?
				end
			end

			algorithm = 0
			while this_round.length != @matches
				this_round = gen_matches(algorithm)
				algorithm += 1
			end

			# Great... we have generated enough matches for this round.
			@generated_matches += this_round
			@round += 1
		}
	end

	# Simple rearrangement based on sorting the array of players.
	def soft_rearrange!
		@players = table_by_score
	end

	# Hard (and slow) rearrange. This will shuffle the players in the same bracket.
	def hard_rearrange!
		scores = []
		@players.each { |player| scores << player.score unless scores.include?(player.score) }
		scores.each do |score|
			# Select those with same score
			players_tmp = @players.select { |player| player.score == score }
			next if players_tmp.length <= 1      # If not more than one, get next group
			# Great... we have a group. Remove them from the main array
			@players.delete_if { |player| player.score == score }
			# Shuffle the temp array
			players_tmp.shuffle!
			# Give it back to the main array
			@players += players_tmp
		end
		# Sort it again in the end
		soft_rearrange!
	end

	# Calculate the maximum number of allowed rearrangements
	#
	# (This is empirical... now set to the number of players)
	def max_rearranges
		@players.length
	end

	# Generate matches inside a round (this is auxiliary function to #checkout_match)
	#
	# algorithm:: 0 - direct; 1 - try hard_rearrange; 2 - try repetition of matches.
	def gen_matches(algorithm)
		played_this_turn = []
		matches = []
		@players.each do |p1|
			next if played_this_turn.include?(p1)       # cannot play twice in the same round
			next if p1.matches != @round                # exceeded number of matches in a round
			@players.each do |p2|
				next if played_this_turn.include?(p2)     # cannot play twice in the same round
				next if p1 == p2                          # player cannot play against itself
				next if has_match?(p1, p2)                # cannot repeat matches (this is a major source of problems
				                                          # ... with few players - and the reason for hard_rearrange!)
				next if p2.matches != @round              # exceeded number of matches in a round (e.g.: received a bye already)
				played_this_turn << p1
				played_this_turn << p2
				matches << Match.new(p1, p2)
				break
			end
		end

		case algorithm
			when 0 then
				# Do nothing different.
				return matches
			when 1 then
				# So we'll rearrange it the "hard" (and slow) way, trying to sort the problem out.
				while @rearranges < max_rearranges and matches.length != @matches
					@rearranges += 1
					hard_rearrange!
					matches = gen_matches(algorithm)
				end
				return matches
			when 2 then
				# Well... hard rearrangements have limitations... Let's see if we're allowed to repeat matches.
				if ! @can_repeat_matches
					# Humpf... Be more flexible!
					raise MaxRearranges
				else
					# Yes... we'll allow the generation of an already played match. Let's find out with one.
					find_matches_to_repeat(matches) do |match|
						matches << match
					end
					if matches.length != @matches
						# Well... we tried!
						raise RepetitionExhausted
					end
				end
				return matches
			else
				# Oops... using black magic?
				raise UnknownAlgorithm
		end
	end

	# Find a good match to repeat given an array of matches (this is auxiliary function to #gen_next_round)
	#
	# round:: matches already generated in this round
	# block:: the receiver of the matches.
	def find_matches_to_repeat(round, &block)
		puts ">>> Here be dragons <<<"
		players = []
		round.each do |match|
			players << match.p1
			players << match.p2
		end

		have_not_played_yet = @players - players
		@committed_matches.reverse.each do |match|
			if have_not_played_yet.include?(match.p1) and \
			   have_not_played_yet.include?(match.p2) and \
				 ! @repeated_matches.include?([match.p1, match.p2]) and \
				 ! @repeated_matches.include?([match.p2, match.p1])

				have_not_played_yet.delete(match.p1)
				have_not_played_yet.delete(match.p2)
				@repeated_matches << [match.p1, match.p2]
				@repeated_matches << [match.p2, match.p1]
				yield Match.new(match.p1, match.p2)
			end
		end
	end

	def get_player_by_id(player_id)
		@players.detect { |player| player.id == player_id }
	end

	def get_match_by_p1_and_p2(array, p1_id, p2_id)
		array.detect { |m| (m.p1.id == p1_id and m.p2.id == p2_id) or (m.p2.id == p1_id and m.p1.id == p2_id) }
	end

end # of class Tournament

# Player Exceptions
class AlreadyByed < Exception; def message; "Already received a bye!"; end; end

# Match Exceptions
class AlreadyDecided < Exception; def message; "This match is already decided!"; end; end

# Tournament Exceptions
class RepeatedPlayersIds < Exception; def message; "Repeated player ids detected!"; end; end
class PlayerExists < Exception; def message; "This player already exist!"; end; end
class MatchExists < Exception; def message; "This match already exist!"; end; end
class MatchNotCheckedOut < Exception; def message; "This match has not been checked out!"; end; end
class EndOfTournament < Exception; def message; "This tournament reached the end!"; end; end
class StillTied < Exception; def message; "We have a difficult tie to break. Try flipping a coin."; end; end
class StillRunning < Exception; def message; "The Tournament has not ended yet."; end; end
class MaxRearranges < Exception; def message; "Reached maximum number of rearrangements allowed."; end; end
class RepetitionExhausted < Exception; def message; "Allowing match repetition as last resort was not enough."; end; end
class UnknownAlgorithm < Exception; def message; "Match generation algorithm unknown."; end; end

end # of module RSwiss

# vim: set ts=2:
