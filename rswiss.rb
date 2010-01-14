require 'thread'
class Player
	attr_reader :matches, :score, :id, :opponents, :c_score

	# Initializes a new Player
	def initialize(id)
		@id = id
		@score = 0
		@matches = 0
		@mutex = Mutex.new
		@byed = false
		@opponents = []
		@c_score = 0
	end

	def inspect
		sprintf("#<%s:%#x @id=%d @score=%.1f @buchholz_score=%.1f @c_score=%.1f @opp_c_score=%.1f @matches=%d @byed=%s>", self.class.name, self.__id__, @id, @score, buchholz_score, @c_score, opp_c_score, @matches, @byed.inspect)
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
		raise RuntimeError, "Already received a bye!" if @byed
		@mutex.synchronize {
			@matches += 1
			@score += 1.0
			@byed = true
		}
	end

	# Add an opponent to the list of opponents (important to calculate the Buchholz score)
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
	attr_reader :p1, :p2, :result, :initial_score

	def initialize(p1, p2)
		@p1 = p1
		@p2 = p2
		@initial_score = [ @p1.score, @p2.score ]
		@result = nil
	end

	def decide(outcome)
		raise RuntimeError, "Already decided!" unless @result.nil?

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
				raise RuntimeError, "A match can be decided by 0, 1 or 2"
		end
		@p1.add_opponent(@p2)
		@p2.add_opponent(@p1)
		@result = outcome
	end
end

class Tournament
	attr_reader :round, :pending_matches

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
	end

	def begin!
		@begun = true
	end

	def add_player(player)
		raise RuntimeError, "Already begun!" if @begun
		raise RuntimeError, "Player already there!" if has_player?(player.id)

		@players << player
	end

	def has_match?(p1, p2)
		! (@matches.detect { |match| ((match.p1.id == p1.id and match.p2.id == p2.id) or (match.p2.id == p1.id and match.p1.id == p2.id)) }).nil?
	end

	def has_player?(id)
		! (@players.detect { |player| player.id == id }).nil?
	end

	def rounds
		raise RuntimeError, "Not begun!" unless @begun

		if @rounds.nil?
			@rounds = (Math.log(@players.length) / Math.log(2)).ceil
		end
		@rounds
	end

	def end_reached?
		raise RuntimeError, "Not begun!" unless @begun
		@round >= rounds and @pending_matches.empty? and @generated_matches.empty?
	end

	def get_next_match
		raise RuntimeError, "Not begun!" unless @begun
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

	def put_match(match)
		raise RuntimeError, "This match doesn't have a result yet!" if match.result.nil?
		raise RuntimeError, "Already have that match!" if has_match?(match.p1, match.p2)
		raise RuntimeError, "We reached the end of the tournament!" if end_reached?

		@mutex.synchronize { 
			@matches << match
			@pending_matches.delete(match)
		}
	end

	def final_chart
		raise RuntimeError, "Tournament had not ended yet!" unless end_reached?
		@players.sort { |a, b| b.score <=> a.score }
	end

	def highest_score
		chart = final_chart
		chart[0].score
	end

	def lowest_score
		chart = final_chart
		chart[-1].score
	end

	def is_tied?
		target = highest_score
		top_players = @players.reject { |player| player.score < target }
		top_players.length != 1
	end

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
			return [ top_player2[0], "Opponent's Cumulative Score" ]
		else
			raise RuntimeError, "We have a difficult to break tie!"
		end
	end

	private

	def gen_next_round
		raise RuntimeError, "Still #{@pending_matches.length} matches to be returned." unless @pending_matches.empty?
		raise RuntimeError, "We reached the end of the tournament!" if end_reached?

		@mutex.synchronize {
			n_matches = (@players.length/2).floor
			this_round = []
			@bye_factor = 1
			@round == 0 ? @players.shuffle! : soft_rearrange!
			if ! last.nil?
				begin
					last.bye
				rescue RuntimeError
					@round == 0 ? @players.shuffle! : bye_detected!
					retry
				end
			end
			begin
				gen_matches do |match|
					this_round << match
				end
				raise RuntimeError if this_round.length != n_matches
			rescue RuntimeError
				@rearranges += 1
				raise StandardError,"Maximum number of rearranges reached (#{max_rearranges})." if @rearranges >= max_rearranges
				hard_rearrange!
				this_round = []
				retry
			end
			@generated_matches += this_round
			@round += 1
		}
	end

	def soft_rearrange!
		@players.sort! { |a, b| b.score <=> a.score }
	end

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

	def max_rearranges
		@players.length
	end

	def gen_matches(&block)
		played_this_turn = []
		@players.each do |p1|
			next if played_this_turn.include?(p1)
			@players.each do |p2|
				next if played_this_turn.include?(p2)
				next if p1 == p2              # Player cannot play itself
				next if has_match?(p1, p2)    # Cannot repeat matches
				next if p1.matches != @round or p2.matches != @round
				played_this_turn << p1
				played_this_turn << p2
				yield Match.new(p1, p2)
				break
			end
		end
	end

	def bye_detected!
		tail = []
		0.upto(@bye_factor) do
			tail << @players.pop
		end
		@players.push tail.pop
		@bye_factor += 1
		@players += tail
	end

	def last
		@players.length.odd? ? @players.last : nil
	end

end

# vim: set ts=2:
