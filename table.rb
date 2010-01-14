require 'thread'

class Player
	attr_reader :name, :id

	def initialize(name)
		@id = get_next_id
		@name = name
	end

	private

	def get_next_id
		@@id_ptr ||= 0
		@@id_ptr += 1
		@@id_ptr
	end
end

class SMatch
	WINNER = 1
	LOOSER = -1
	DRAW = 0

	attr_reader :p1, :p2, :result
	def initialize(p1, p2, result = nil)
		@p1 = p1
		@p2 = p2
		@result = result
		if @p1.name == "__LEAVE__"
			@result = SMatch::LOOSER
		end
		if @p2.name == "__LEAVE__"
			@result = SMatch::WINNER
		end
	end

	def result=(result)
		raise RuntimeError, "Not in range" unless [-1,0,1].include?(result)
		raise RuntimeError, "Already filled" unless @result.nil?
		@result = result
	end

	def equals?(match)
		@p1 == match.p1 and @p2 == match.p2
	end
end

class Table
	def initialize
		@players = Hash.new
		@all_included = false
		@rounds = nil
		@round = 0
		@available_matches = []
		@given_matches = []
		@run_matches = []
		@mutex = Mutex.new
	end

	def has_player?(player)
		return true if @players.include?(player.id)
		mark = false
		@players.each_value do |p|
			break if mark
			mark = true if p.name == player.name
		end
		return mark
	end

	def add_player(player)
		raise RuntimeError, "Players named __LEAVE__ are used internally" if player.name == "__LEAVE__"
		raise RuntimeError, "Already included" if has_player?(player)
		raise RuntimeError, "All included!" if @all_included

		@players[player.id] = player
	end

	def del_player(player)
		raise RuntimeError, "You cannot delete __LEAVE__ player" if player.name == "__LEAVE__"
		raise RuntimeError, "Not included" unless has_player?(player)
		raise RuntimeError, "All included!" if @all_included

		@players.delete_if { |id, p| player.id == id or p.name == player.name }
	end

	def all_included!
		@all_included = true
	end

	def rounds
		raise RuntimeError, "Not done including" unless @all_included

		if @rounds.nil?
			if @players.length.odd?
				leave_player = Player.new("__LEAVE__")
				@players[leave_player.id] = leave_player
			end
			@rounds = (Math.log(@players.length) / Math.log(2)).ceil
		end
		@rounds
	end

	def pending_matches
		@given_matches
	end

	def next_match(random = false)
		@mutex.synchronize {
			if @available_matches.empty?
				# Have no more matches, have to generate some.
				if @round == rounds
					# Oops. That was the last round. Rests.
					raise RuntimeError, "I've run all matches already."
				else
					if @given_matches.empty?
						# On to next round
						gen_matches
						@round += 1
					else
						# Oops...
						raise RuntimeError, "Haven't returned all checked out matches, have you? Check #pending_matches"
					end
				end
			end
			@available_matches.shuffle! if random
			mat = @available_matches.shift
			@given_matches << mat
			return mat
		}
	end

	def feed_match(match)
		raise RuntimeError, "No result provided" if match.result.nil?
		@mutex.synchronize {
			@given_matches.each_with_index do |mat, i|
				if mat.equals?(match)
					@run_matches << match
					@given_matches.delete_at(i)
					break
				end
			end
		}
	end

	def scores
		sco = Hash.new
		@players.each_key { |player_id| sco[player_id] = 0 }
		@run_matches.each do |mat|
			sco[mat.p1.id] += mat.result
			sco[mat.p2.id] -= mat.result
		end
		return sco
	end

	def run_match?(p1, p2)
		ret = false
		@run_matches.each do |mat|
			(ret = true; break) if mat.p1 == @players[p1] and mat.p2 == @players[p2]
			(ret = true; break) if mat.p2 == @players[p1] and mat.p1 == @players[p2]
		end
		return ret
	end

	def gen_matches
		if @round == 0
			# First round. Just random it.
			first_half = @players.keys[0...@players.keys.length/2]
			second_half = @players.keys[@players.keys.length/2..-1]
			first_half.each_with_index do |player_id, i|
				@available_matches << SMatch.new(@players[player_id], @players[second_half[i]])
			end
		else
			# Now we have to consider past matches
			sorted_scores = scores.sort { |a, b| a[1]<=>b[1] }
			sorted_scores.reverse!
			a = nil; a_index = 0
			b = nil; b_index = 1
			loop do
				if a.nil?
					a = sorted_scores[a_index][0]
				end
				if b.nil?
					b = sorted_scores[b_index][0]
				end
				break if a.nil? or b.nil?
				if ! run_match?(a, b)
					@available_matches << SMatch.new(@players[a], @players[b])
					a = nil; a_index += 1
					b = nil; b_index = a_index + 1
					next
				else
					b = nil; b_index += 1
					if b_index >= sorted_scores.length
						a = nil; a_index += 1
						b = nil; b_index = a_index + 1
						if a_index >= sorted_scores.length
							# Generated all matches we could
							break
						end
					end
					next
				end
			end
		end
	end

end


