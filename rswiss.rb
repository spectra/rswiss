require 'thread'
class Player
	class AlreadyByed < RuntimeError; def message; "Already received a bye!"; end; end

	attr_reader :matches, :score, :id, :opponents, :c_score, :wins

	# Initializes a new Player
	#
	# id:: id of the player
	def initialize(id)
		@id = id
		@score = 0
		@matches = 0
		@mutex = Mutex.new
		@byed = false
		@opponents = []
		@c_score = 0
		@wins = 0
	end

	# :nodoc:
	def inspect
		sprintf("#<%s:%#x @id=%d @matches=%d @byed=%s @score=%.1f @buchholz_score=%.1f @c_score=%.1f @opp_c_score=%.1f @wins=%d>", self.class.name, self.__id__, @id, @matches, @byed.inspect, @score, buchholz_score, @c_score, opp_c_score, @wins)
	end

	# Mark a lost game
	def lost
		@matches += 1
	end

	# Mark a won game
	def won
		@mutex.synchronize {
			@matches += 1
			@score += 1.0
			@c_score += @score
			@wins += 1
		}
	end

	# Mark a draw
	def draw
		@mutex.synchronize {
			@matches += 1
			@score += 0.5
			@c_score += @score
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

	# Add an opponent to the list of opponents (important to calculate tie-breaking scores)
	def add_opponent(opponent)
		@opponents << opponent
	end
	
	# Calculate the Buchholz score
	def buchholz_score
		scores = []
		@opponents.each do |opponent|
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
		sum = 0
		@opponents.each do |opponent|
			sum += opponent.c_score
		end
		return sum
	end

end

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
				@p1.won
				@p2.lost
			when 2 then
				@p1.lost
				@p2.won
			when 0 then
				@p1.draw
				@p2.draw
			else
				raise ArgumentError, "A match can be decided by 0, 1 or 2."
		end
		@p1.add_opponent(@p2)
		@p2.add_opponent(@p1)
		@result = outcome
	end
end

class Tournament
	class AlreadyBegun < RuntimeError; def message; "This tournament has already begun!"; end; end
	class NotBegun < RuntimeError; def message; "This tournament has not begun yet!"; end; end
	class PlayerExists < RuntimeError; def message; "This player already exist!"; end; end
	class MatchExists < RuntimeError; def message; "This match already exist!"; end; end
	class MatchNotCheckedOut < RuntimeError; def message; "This match has not been checked out!"; end; end
	class EndOfTournament < RuntimeError; def message; "This tournament reached the end!"; end; end
	class StillTied < RuntimeError; def message; "We have a difficult tie to break. Try flipping a coin."; end; end
	class MaxRearranges < RuntimeError; def message; "Reached maximum number of rearrangements allowed (#{max_rearranges})."; end; end
	class RepeatitionExhausted < RuntimeError; def message; "Allowing mqatch repetition as last resort was not enough."; end; end

	attr_reader :round, :pending_matches

	# Initializes a new tournament
	def initialize
		@matches = []
		@players = []
		@begun = false
		@round = 0
		@bye_factor = 0
		@rounds = nil

		@generated_matches = []
		@pending_matches = []
		@mutex = Mutex.new
		@rearranges = 0

		@can_repeat_matches = false
		@repeated_matches = []
	end

	# Set the tournament to begin (prevent new players to enter)
	def begin!
		@begun = true
	end

	# Allow the repetition of matches (as last resort)
	def allow_repeated_matches
		raise AlreadyBegun if @begun
		@can_repeat_matches = true
	end

	# Forbid the repetition of matches
	def forbid_repeated_matches
		raise AlreadyBegun if @begun
		@can_repeat_matches = false
	end

	# Get the number of repeated matches
	def repeated_matches
		@repeated_matches.length / 2
	end

	# Add a new player (only before issuing a #begin!)
	#
	# player:: Player to be added
	def add_player(player)
		raise AlreadyBegun if @begun
		raise PlayerExists if has_player?(player.id)

		@players << player
	end

	# Test if a match have occurred in this tournament. The order doesn't matter
	# (Player A versus Player B) == (Player B versus Player A)
	#
	# p1:: Player 1
	# p2:: Player 2
	def has_match?(p1, p2)
		! (@matches.detect { |match| ((match.p1.id == p1.id and match.p2.id == p2.id) or (match.p2.id == p1.id and match.p1.id == p2.id)) }).nil?
	end

	# Test if we already have this player.
	#
	# id:: Player's id
	def has_player?(id)
		! (@players.detect { |player| player.id == id }).nil?
	end

	# Calculate the number of needed rounds (after #begin!)
	def rounds
		raise NotBegun unless @begun

		if @rounds.nil?
			@rounds = (Math.log(@players.length) / Math.log(2)).ceil
		end
		@rounds
	end

	# Have we reached the end of the tournament?
	def end_reached?
		raise NotBegun unless @begun
		@round >= rounds and @pending_matches.empty? and @generated_matches.empty?
	end

	# Checkout the next match of the tournament
	def get_next_match
		raise NotBegun unless @begun
		if @generated_matches.empty?
			gen_next_round
			get_next_match
		else
			match = nil
			@mutex.synchronize {
				match = @generated_matches.pop
				@pending_matches.push match
			}
			return match
		end
	end

	# Commit a checked-out match back in
	#
	# match:: a Match
	def put_match(match)
		raise ArgumentError, "This match doesn't have a result yet!" if match.result.nil?
		raise MatchExists if has_match?(match.p1, match.p2) and ! @can_repeat_matches
		raise EndOfTournament if end_reached?
		unless @pending_matches.detect { |m| (m.p1.id == match.p1.id and m.p2.id == match.p2.id) or (m.p2.id == match.p1.id and m.p1.id == match.p2.id) }
			raise MatchNotCheckedOut
		end

		@mutex.synchronize { 
			@matches << match
			@pending_matches.delete_if { |m| (m.p1.id == match.p1.id and m.p2.id == match.p2.id) or (m.p2.id == match.p1.id and m.p1.id == match.p2.id) }
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

	# Do we have a tie?
	def is_tied?
		target = highest_score
		top_players = @players.reject { |player| player.score < target }
		top_players.length != 1
	end

	# Who is the winner?
	#
	# The winner is decided using some tie-breaking criteria if needed:
	# Direct Score > Median Buchholz Score > Cumulative Score > Opponent's Cumulative Score > Number of Wins
	#
	# An array is returned with the winner and the criteria used.
	# An Exception is raised if the tie is too hard to break.
	def winner
		# Decide the winner just by the score
		target = highest_score
		top_player0 = @players.reject { |player| player.score < target }
		if top_player0.length == 1
			# Great! We have a winner!
			return [ top_player0[0], "Direct Score" ]
		end

		# First tie-break criteria: Buchholz score
		scores = []
		top_player0.each do |player|
			scores << player.buchholz_score
		end
		top_player1 = top_player0.reject { |player| player.buchholz_score < scores.max }
		if top_player1.length == 1
			# Great! We have a winner!
			return [ top_player1[0], "Buchholz Score" ]
		end

		# Second tie-break criteria: Cumulative Score
		c_scores = []
		top_player1.each { |player| c_scores << player.c_score }
		top_player2 = top_player1.reject { |player| player.c_score < c_scores.max }
		if top_player2.length == 1
			# Great! We have a winner!
			return [ top_player2[0], "Cumulative Score" ]
		end

		# Third tie-break criteria: Opponent's Cumulative Score
		opp_c_scores = []
		top_player2.each { |player| opp_c_scores << player.opp_c_score }
		top_player3 = top_player2.reject { |player| player.opp_c_score < opp_c_scores.max }
		if top_player3.length == 1
			# Great! We have a winner!
			return [ top_player3[0], "Opponent's Cumulative Score" ]
		end

		# Fourth tie-breaking criteria: Number of Wins
		wins = []
		top_player3.each { |player| wins << player.wins }
		top_player4 = top_player3.reject { |player| player.wins < wins.max }
		if top_player4.length == 1
			# Great! We have a winner!
			return [ top_player4[0], "Number of Wins" ]
		else
			raise StillTied
		end
	end

	private

	# Generate the next round of matches
	def gen_next_round
		raise RuntimeError, "Still #{@pending_matches.length} matches to be returned." unless @pending_matches.empty?
		raise EndOfTournament if end_reached?

		@mutex.synchronize {
			n_matches = (@players.length/2).floor
			this_round = []
			@bye_factor = 1	                                  # Reset @bye_factor (just in case we need it)
			@round == 0 ? @players.shuffle! : soft_rearrange! # round 0 is random

			# Do we have a last unpaired player?
			if ! last.nil?
				begin
					# Yes! Try to bye it.
					last.bye
				rescue RuntimeError
					# Oops... Already have a bye. #bye_detected! will try to solve it using @bye_factor.
					@round == 0 ? @players.shuffle! : bye_detected!
					retry
				end
			end

			begin
				gen_matches do |match|
					this_round << match
				end

				# If we haven't generated enough matches, there might be a problem with our "classification"...
				raise RuntimeError if this_round.length != n_matches
			rescue RuntimeError
				# ... so we'll rearrange it the "hard" (and slow) way, trying to sort the problem out.
				@rearranges += 1
				if @rearranges < max_rearranges
					# Not done with you yet, lady...
					hard_rearrange!
					this_round = []
					retry
				else
					# Well... hard rearrangements have limitations... Let's see if we're allowed to repeat matches.
					puts ">>> Here be dragons <<<"
					if ! @can_repeat_matches
						# Humpf... Be more flexible!
						raise MaxRearranges
					else
						# Yes... we'll allow the generation of an already played match. Let's find out with one.
						find_matches_to_repeat(this_round) do |match|
							this_round << match
						end
						if this_round.length != n_matches
							# Well... we tried!
							raise RepetitionExhausted
						end
					end
				end
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

	# Hard (and slow) rearrange. This will shuffle the players with the same score.
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

	# Generate matches inside a round (this is auxiliary function to #gen_next_round)
	#
	# block:: block to consume the matches while they're being produced.
	def gen_matches(&block)
		played_this_turn = []
		@players.each do |p1|
			next if played_this_turn.include?(p1)       # cannot play twice in the same round
			next if p1.matches != @round                # exceeded number of matches in a round
			@players.each do |p2|
				next if played_this_turn.include?(p2)     # cannot play twice in the same round
				next if p1 == p2                          # player cannot play against itself
				next if has_match?(p1, p2)                # cannot repeat matches (this is a major source of problems
				                                          # ... with few players - and the reason for hard_rearrange!)
				next if p2.matches != @round              # exceeded number of matches in a round
				played_this_turn << p1
				played_this_turn << p2
				yield Match.new(p1, p2)
				break
			end
		end
	end

	# Applies some black magic to try to sort out the problem of last
	# players that already received a bye.
	#
	# This use @bye_factor to traverse the @players array from bottom up.
	def bye_detected!
		tail = []
		0.upto(@bye_factor) do
			tail << @players.pop
		end
		@players.push tail.pop
		@bye_factor += 1
		@players += tail
	end

	# Returns the last unpaired player (or nil if all can be paired).
	def last
		@players.length.odd? ? @players.last : nil
	end

	# Find a good match to repeat given an array of matches (this is auxiliary function to #gen_next_round)
	#
	# round:: matches already generated in this round
	# block:: the receiver of the matches.
	def find_matches_to_repeat(round, &block)
		players = []
		round.each do |match|
			players << match.p1
			players << match.p2
		end

		have_not_played_yet = @players - players
		@matches.reverse.each do |match|
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
