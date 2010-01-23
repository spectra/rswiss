require 'thread'

# Class to represent a Player (this is used internally by Tournament)
class Player
	class AlreadyByed < RuntimeError; def message; "Already received a bye!"; end; end

	attr_reader :matches, :score, :id, :c_score, :wins

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
	def inspect
		sprintf("#<%s:%#x @id=%d @matches=%d @byed=%s @score=%.1f @buchholz_score=%.1f @c_score=%.1f @opp_c_score=%.1f @wins=%d, @neustadtl_score=%.2f>", self.class.name, self.__id__, @id, @matches, @byed.inspect, @score, buchholz_score, @c_score, opp_c_score, @wins, neustadtl_score)
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
end

# Class to represent a Match (this is used internally by Tournament)
class Match
	class AlreadyDecided < RuntimeError; def message; "This match is already decided!"; end; end

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
end

class Tournament
	class RepeatedPlayersIds < RuntimeError; def message; "Repeated player ids detected!"; end; end
	class PlayerExists < RuntimeError; def message; "This player already exist!"; end; end
	class MatchExists < RuntimeError; def message; "This match already exist!"; end; end
	class MatchNotCheckedOut < RuntimeError; def message; "This match has not been checked out!"; end; end
	class EndOfTournament < RuntimeError; def message; "This tournament reached the end!"; end; end
	class StillTied < RuntimeError; def message; "We have a difficult tie to break. Try flipping a coin."; end; end
	class MaxRearranges < RuntimeError; def message; "Reached maximum number of rearrangements allowed."; end; end
	class RepetitionExhausted < RuntimeError; def message; "Allowing match repetition as last resort was not enough."; end; end
	class UnknownAlgorithm < RuntimeError; def message; "Match generation algorithm unknown."; end; end

	attr_reader :round, :rounds, :checkedout_matches, :matches

	# Initializes a new tournament
	#
	# players_array:: array of player ids.
	# allow_repeated_matches:: boolean defining if we allow repeating matches as last resort (default: false).
	def initialize(players_array, allow_repeated_matches = false)
		raise RepeatedPlayerIds if players_array != players_array.uniq

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

		# Match Maker
		@mutex = Mutex.new
		@generated_matches = []
		@checkedout_matches = []
		@committed_matches = []
		@repeated_matches = []
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
	# match:: a Match
	def commit_match(match)
		raise ArgumentError, "This match doesn't have a result yet!" if match.result.nil?
		raise MatchExists if has_match?(match.p1, match.p2) and ! @can_repeat_matches
		raise EndOfTournament if ended?
		unless @checkedout_matches.detect { |m| (m.p1.id == match.p1.id and m.p2.id == match.p2.id) or (m.p2.id == match.p1.id and m.p1.id == match.p2.id) }
			raise MatchNotCheckedOut
		end

		@mutex.synchronize { 
			@committed_matches << match
			@checkedout_matches.delete_if { |m| (m.p1.id == match.p1.id and m.p2.id == match.p2.id) or (m.p2.id == match.p1.id and m.p1.id == match.p2.id) }
		}
	end

	# Return an array of the players sorted by score
	def final_chart
		@players.sort { |a, b| b.score <=> a.score }
	end

	# Get the first player with the highest score
	def highest_score
		chart = final_chart
		chart[0].score
	end

	# Get the last player with the lowest score
	def lowest_score
		chart = final_chart
		chart[-1].score
	end

	# Who is the winner?
	#
	# The winner is decided using some tie-breaking criteria if needed:
	# Direct Score > Median Buchholz Score > Neustadtl Score > Cumulative Score > Opponent's Cumulative Score > Number of Wins
	#
	# An array is returned with the winner and the criteria used.
	# An Exception is raised if the tie is too hard to break.
	def winner
		# Decide the winner just by the score
		target = highest_score
		top_player0 = @players.reject { |player| player.score < target }
		if top_player0.length == 1
			# Great! We have a winner!
			return [ top_player0[0], "Conventional Score" ]
		end

		# First tie-break criteria: Buchholz score
		buchholz_scores = []
		top_player0.each do |player|
			buchholz_scores << player.buchholz_score
		end
		top_player1 = top_player0.reject { |player| player.buchholz_score < buchholz_scores.max }
		if top_player1.length == 1
			# Great! We have a winner!
			return [ top_player1[0], "Buchholz Score" ]
		end

		# Second tie-break criteria: Neustadtl Score
		neustadtl_scores = []
		top_player1.each { |player| neustadtl_scores << player.neustadtl_score }
		top_player2 = top_player1.reject { |player| player.neustadtl_score < neustadtl_scores.max }
		if top_player2.length == 1
			# Great! We have a winner!
			return [ top_player2[0], "Neustadtl Score" ]
		end

		# Third tie-break criteria: Cumulative Score
		c_scores = []
		top_player2.each { |player| c_scores << player.c_score }
		top_player3 = top_player2.reject { |player| player.c_score < c_scores.max }
		if top_player3.length == 1
			# Great! We have a winner!
			return [ top_player3[0], "Cumulative Score" ]
		end

		# Fourth tie-break criteria: Opponent's Cumulative Score
		opp_c_scores = []
		top_player3.each { |player| opp_c_scores << player.opp_c_score }
		top_player4 = top_player3.reject { |player| player.opp_c_score < opp_c_scores.max }
		if top_player4.length == 1
			# Great! We have a winner!
			return [ top_player4[0], "Opponent's Cumulative Score" ]
		end

		# Fifth tie-breaking criteria: Number of Wins
		wins = []
		top_player4.each { |player| wins << player.wins }
		top_player5 = top_player4.reject { |player| player.wins < wins.max }
		if top_player5.length == 1
			# Great! We have a winner!
			return [ top_player5[0], "Number of Wins" ]
		else
			raise StillTied
		end
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
		@players.sort! { |a, b| b.score <=> a.score }
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

end

# vim: set ts=2:
