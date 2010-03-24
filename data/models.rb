# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 43):
# <pablo@propus.com.br> wrote this file and it's provided AS-IS, no
# warranties. As long as you retain this notice you can do whatever you
# want with this stuff. If we meet some day, and you think this stuff is
# worth it, you can buy me a beer in return."
# ----------------------------------------------------------------------

require 'sequel'
require 'thread'

module SSwiss

class Tournament < Sequel::Model
	attr_accessor :criteria

	def validate
		errors.add(:n_players, "can't be empty") if self.n_players.nil?
	end

	def before_save
		super
		self.additional_rounds = 0 if self.additional_rounds.nil?
		self.rounds = (Math.log(self.n_players) / Math.log(2)).ceil + self.additional_rounds.abs
		self.matches_per_round = (self.n_players/2).floor
	end

	def criteria
		if @criteria.nil?
			[ :score, :buchholz_score, :neustadtl_score, :c_score, :opp_c_score, :wins ]
		else
			@criteria
		end
	end

	def inject_players(array)
		raise RuntimeError, "The length of the provided array must match :n_players" if array.length != self.n_players
		raise RepeatedPlayerIds if array.uniq.sort != array.sort

		array.each { |player_id|
			player = Player.create(:tournament => self, :in_tournament_id => player_id)
			player.save
		}
	end

	def players(ordering = :raw)
		myplayers = Player.dataset.filter(:tournament_id => self.id).all
		case ordering
			when :random then
				myplayers.shuffle
			when :criteria then
				myplayers.sort do |a, b|
					a_side = []
					b_side = []
					criteria.each do |func|
						a_side << a.send(func)
						b_side << b.send(func)
					end
					b_side <=> a_side
				end
			when :score, :soft then
				myplayers.sort { |a, b| b.score <=> a.score }
			when :hard then
				scores = []
				myplayers.each { |player| scores << player.score unless scores.include?(player.score) }
				scores.each do |score|
					# Select those with same score
					players_tmp = myplayers.select { |player| player.score == score }
					next if players_tmp.length <= 1      # If not more than one, get next group
					# Great... we have a group. Remove them from the main array
					myplayers.delete_if { |player| player.score == score }
					# Shuffle the temp array
					players_tmp.shuffle!
					# Give it back to the main array
					myplayers += players_tmp
				end
				# Sort it again in the end
				myplayers.sort { |a, b| b.score <=> a.score }
			else
				# This include the :raw case
				myplayers
		end
	end

	def player_ids
		my_ids = []
		players.each { |player|
			my_ids << player.id
		}
		return my_ids
	end

	def ended?
		self.round >= self.rounds and checkedout_matches.empty? and available_matches.empty?
	end

	# All matches from this tournament
	def all_matches
		Match.dataset.filter(:tournament_id => self.id).all
	end

	# Matches that already have a result
	def committed_matches
		Match.dataset.filter(:tournament_id => self.id).filter(:result => [-1, 0, 1]).all
	end

	# Matches that were checkedout but have not yet being committed
	def checkedout_matches
		Match.dataset.filter(:tournament_id => self.id).filter(:result => nil).filter(:checked_out => true).all
	end

	# Matches that doesn't have a result and were not checked-out yet
	def available_matches
		Match.dataset.filter(:tournament_id => self.id).filter(:result => nil).filter(:checked_out => false).filter(:planned => false).all
	end

	# Matches that were repeated
	def repeated_matches
		Match.dataset.filter(:tournament_id => self.id).filter(:repeated => true).all.length
	end

	# Matches for a given round
	def round_matches(round)
		Match.dataset.filter(:tournament_id => self.id).filter(:round => round).all
	end

	# Matches in planning stage
	def planned_matches(round)
		Match.dataset.filter(:tournament_id => self.id).filter(:round => round).filter(:planned => true).all
	end

	# Checkout the next match
	def checkout_match
		@mutex ||= Mutex.new

		mymatch = available_matches[0]
		if mymatch.nil?
			raise GeneratingRound if @mutex.locked?
			gen_next_round
			return checkout_match
		end
		mymatch.checked_out = true
		mymatch.save
		return mymatch
	end

	# For compatibility
	def commit_match(match)
		match.save
	end

	def has_match?(p1, p2)
		! (Match[:p1_id => p1.id, :p2_id => p2.id] or Match[:p2_id => p1.id, :p1_id => p2.id]).nil?
	end

	# Who is the winner?
	#
	# The winner is decided using some tie-breaking criteria if needed:
	#
	# An array is returned with the winner and the criteria used.
	# An Exception is raised if the tie is too hard to break.
	def winner(mycriteria = nil)
		raise StillRunning unless ended?

		top_players = players.clone
		mycriteria = self.criteria if mycriteria.nil?
		while ! mycriteria.empty?
			this_time_criteria = mycriteria.shift
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

	private

	# Generate the next round of matches
	def gen_next_round
		raise RuntimeError, "Still #{checkedout_matches.length} matches to be returned." unless checkedout_matches.empty?
		raise EndOfTournament if ended?

		@mutex.synchronize {
			myplayers = self.round == 0 ? players(:random) : players(:soft) # round 0 is random

			# Will we have a last unpaired player?
			if myplayers.length.odd?
				# Yes :-) Let's find someone to bye!
				myplayers.reverse.each do |player|
					# Stop looking for if we found it.
					unless player.byed
						player.byed = true
						player.matches +=1
						player.save
						break
					end
				end
			end

			# First, try it plain
			gen_matches(myplayers, self.round)

			# Oops... not enough matches. We'll try to traverse the match array to find
			# some to delete and regenerate the round only with the last players shuffled.
			if self.matches_per_round != round_matches(self.round).length
				self.planned_matches(self.round).reverse.each { |match|
					match.p1.matches -= 1; match.p1.save
					match.p2.matches -= 1; match.p2.save
					match.delete                                                        # delete the match
					lastplayers = myplayers.clone
					lastplayers.delete_if { |player| player.matches != self.round }     # discard those that have already played
					lastplayers.shuffle!                                                # shuffle the array
					gen_matches(lastplayers, self.round)                                # try to generate the last matches
					break if self.matches_per_round == round_matches(self.round).length # try no more if ok.
				}
			end

			# Well... not enough matches yet!
			if self.matches_per_round != round_matches(self.round).length
				# We'll throw the whole round away and we'll try a new rearrange
				planned_matches(self.round).each { |match| match.delete }
				self.n_players.times {
					myplayers = players(:hard)
					gen_matches(my_players, self.round)
					break if self.matches_per_round == round_matches(self.round).length # try no more if ok.
				}
			end

			raise "boom! #{self.matches_per_round} != #{round_matches(self.round).length}" if self.matches_per_round != round_matches(self.round).length

			# Great... we have generated enough matches for this round.
			# Turn the planned flag off
			planned_matches(self.round).each { |match| match.planned = false; match.save }
			# And save the tournament state
			self.round += 1
			self.save
		}
	end

	# Generate matches inside a round (this is auxiliary function to #gen_next_round)
	def gen_matches(myplayers, round)
		myplayers.each do |p1|
			next if p1.matches != round                 # exceeded number of matches in a round
			opponents_of_p1 = p1.opponents
			myplayers.each do |p2|
				next if p1 == p2                          # player cannot play against itself
				next if opponents_of_p1.include?(p2)      # cannot play again
#				next if has_match?(p1, p2)                # cannot repeat matches (this is a major source of problems
				                                          # ... with few players - and the reason for hard_rearrange!)
				next if p2.matches != round               # exceeded number of matches in a round (e.g.: received a bye already)
				m = Match.create(:p1 => p1, :p2 => p2, :tournament => self, :round => round)
				p1.matches += 1; p1.save
				p2.matches += 1; p2.save
				m.save
				break
			end
		end
	end

end # of class Tournament

class Player < Sequel::Model
	many_to_one :tournament

	# :nodoc:
	def inspect
		sprintf("#<%s:%#x id=%d in_tournament_id=%d matches=%d byed=%s score=%.1f buchholz_score=%.1f c_score=%.1f opp_c_score=%.1f wins=%d, neustadtl_score=%.2f>", self.class.name, self.__id__.abs, self.id, self.in_tournament_id, matches, byed.inspect, score, buchholz_score, c_score, opp_c_score, wins, neustadtl_score)
	end

	def validate
		errors.add(:tournament, "can't be empty") if self.tournament.nil?
		errors.add(:in_tournament_id, "can't be empty") if self.in_tournament_id.nil?
	end

	def all_matches
		Match.dataset.filter(:p1_id => self.id).all + Match.dataset.filter(:p2_id => self.id).all
	end

	def decided_matches
		Match.dataset.filter(:p1_id => self.id).filter(:result => [-1, 0, 1]).all + Match.dataset.filter(:p2_id => self.id).filter(:result => [-1, 0, 1]).all
	end

	def undecided_matches
		all_matches - decided_matches
	end

	def opponents
		opponent_ids = []
		decided_matches.each {|match|
			if match.p1_id == self.id
				opponent_ids << match.p2_id
			else
				opponent_ids << match.p1_id
			end
		}
		Player.dataset.filter(:id => opponent_ids).all
	end

	def opps_won
		opponent_ids = []
		decided_matches.each {|match|
			if match.p1_id == self.id
				opponent_ids << match.p2_id if match.result == -1
			else
				opponent_ids << match.p1_id if match.result == 1
			end
		}
		Player.dataset.filter(:id => opponent_ids).all
	end

	def opps_draw
		opponent_ids = []
		decided_matches.each {|match|
			if match.p1_id == self.id
				opponent_ids << match.p2_id if match.result == 0
			else
				opponent_ids << match.p1_id if match.result == 0
			end
		}
		Player.dataset.filter(:id => opponent_ids).all
	end

	def rounds
		if self.byed
			all_matches.length + 1
		else
			all_matches.length
		end
	end

	def score
		to_inject = self.byed ? 1.0 : 0.0
		decided_matches.inject(to_inject) { |sum, match|
			result = match.p2_id == self.id ? match.result : (match.result * (-1))
			case result
				when 0 then
					# Draw means half a point
					sum + 0.5
				when 1 then
					# Victory means a full point
					sum + 1.0
				when -1 then
					# Defeat sums no points
					sum + 0.0
			end
		}
	end

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

	def c_score
		partial_score = 0
		decided_matches.inject(0) { |sum, match|
			result = match.p2_id == self.id ? match.result : (match.result * (-1))
			case result
				when 0 then
					partial_score += 0.5
				when 1 then
					partial_score += 1.0
			end
			sum + partial_score
		}
	end

	def opp_c_score
		opponents.inject(0) { |sum, player|
			sum + player.c_score
		}
	end

	def neustadtl_score
		defeated_sum = opps_won.inject(0)  { |sum, opponent| sum + opponent.score }
		draw_sum     = opps_draw.inject(0) { |sum, opponent| sum + opponent.score }

		return defeated_sum + (draw_sum / 2)
	end

	def wins
		decided_matches.inject(0) { |sum, match|
			result = match.p2_id == self.id ? match.result : (match.result * (-1))
			result == 1 ? sum + 1 : sum + 0
		}
	end

end # of class Player

P1 = P2 = Player

class Match < Sequel::Model
	many_to_one :p1
	many_to_one :p2
	many_to_one :tournament

	# :nodoc:
	def inspect
		sprintf("#<%s:%#x id=%d p1_id=%d p2_id=%d round=%d result=%s planned=%s>", self.class.name, self.__id__.abs, self.id, self.p1.id, self.p2.id, self.round, self.result.inspect, self.planned.inspect)
	end

	def validate
		errors.add(:p1_id, "can't be empty") if self.p1.nil?
		errors.add(:p2_id, "can't be empty") if self.p2.nil?
		errors.add(:tournament, "can't be empty") if self.tournament.nil?
		errors.add(:p1_id, "can't be equal to :p2_id") if self.p1 == self.p2
	end

end # of class Match

# Tournament Exceptions
class RepeatedPlayerIds < Exception; def message; "Repeated player ids detected!"; end; end
class MatchExists < Exception; def message; "This match already exist!"; end; end
class MatchNotCheckedOut < Exception; def message; "This match has not been checked out!"; end; end
class EndOfTournament < Exception; def message; "This tournament reached the end!"; end; end
class StillTied < Exception; def message; "We have a difficult tie to break. Try flipping a coin."; end; end
class StillRunning < Exception; def message; "The Tournament has not ended yet."; end; end
class MaxRearranges < Exception; def message; "Reached maximum number of rearrangements allowed."; end; end
class RepetitionExhausted < Exception; def message; "Allowing match repetition as last resort was not enough."; end; end
class UnknownAlgorithm < Exception; def message; "Match generation algorithm unknown."; end; end
class GeneratingRound < Exception; def message; "Please wait while we generate the next round."; end; end

end # of module SSwiss

