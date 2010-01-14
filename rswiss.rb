require 'thread'
class Player
	attr_reader :matches, :score, :id, :opponents

	def initialize(id)
		@id = id
		@score = 0
		@matches = 0
		@mutex = Mutex.new
		@byed = false
		@opponents = []
	end

	def inspect
		sprintf("#<%s:%#x @id=%d @score=%.1f @buchholz_score=%.1f @matches=%d @byed=%s>", self.class.name, self.__id__, @id, @score, buchholz_score, @matches, @byed.inspect)
	end

	def lost
		@matches += 1
	end

	def won
		@mutex.synchronize {
			@matches += 1
			@score += 1
		}
	end

	def draw
		@mutex.synchronize {
			@matches += 1
			@score += 0.5
		}
	end

	def bye
		raise RuntimeError, "Already received a bye!" if @byed
		@mutex.synchronize {
			@matches += 1
			@score += 1
			@byed = true
		}
	end

	def add_opponent(opponent)
		@opponents << opponent
	end
	
	def buchholz_score
		sum = 0
		@opponents.each do |opponent|
			sum += opponent.score
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
		raise RuntimeError, "We've got a tie!" if is_tied?
		target = highest_score
		top_players = @players.reject { |player| player.score < target }
		top_players[0]
	end

	def tie_break
		raise RuntimeError, "We have no tie!" unless is_tied?
		target = highest_score
		top_player0 = @players.reject { |player| player.score < target }
		scores = []
		top_player0.each do |player|
			scores << player.buchholz_score
		end
		top_player1 = top_player0.reject { |player| player.buchholz_score < scores.max }
		if top_player1.length == 1
			return top_player1[0]
		else
			raise RuntimeError, "We're still tied!"
		end
	end

	private

	def gen_next_round
		raise RuntimeError, "Still #{@pending_matches.length} matches to be returned." unless @pending_matches.empty?
		raise RuntimeError, "We reached the end of the tournament!" if end_reached?

		@mutex.synchronize {
			@bye_factor = 1
			@round == 0 ? @players.shuffle! : rearrange!
			if ! last.nil?
				begin
					last.bye
				rescue RuntimeError
					@round == 0 ? @players.shuffle! : bye_detected!
					retry
				end
			end
			gen_matches do |match|
				@generated_matches << match
			end
			@round += 1
		}
	end

	def rearrange!
		@players.sort! { |a, b| b.score <=> a.score }
	end

	def gen_matches(&block)
		n_matches = (@players.length/2).floor
		played_this_turn = []
		count = 0
		@players.each do |p1|
			next if played_this_turn.include?(p1)
			@players.each do |p2|
				next if played_this_turn.include?(p2)
				next if p1 == p2              # Player cannot play itself
				next if has_match?(p1, p2)    # Cannot repeat matches
				puts "#{p1.matches} / #{p2.matches} / #{@round}"
				played_this_turn << p1
				played_this_turn << p2
				yield Match.new(p1, p2)
				count += 1
				break
			end
			break if count == n_matches     # Already generated enough matches
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
		puts ">>>Last: #{@players.last.id} / #{@players.last.score}"
		@players.length.odd? ? @players.last : nil
	end

end

# vim: set ts=2:
