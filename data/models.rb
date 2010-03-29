# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 43):
# <pablo@propus.com.br> wrote this file and it's provided AS-IS, no
# warranties. As long as you retain this notice you can do whatever you
# want with this stuff. If we meet some day, and you think this stuff is
# worth it, you can buy me a beer in return."
# ----------------------------------------------------------------------

require 'sequel'
require 'thread'

module RSwiss

class Tournament < Sequel::Model
	attr_accessor :criteria

	# Sets the logger for the Tournament Model Class (this is class-wide)
	def Tournament.logger=(logger)
		@@logger = logger
	end

	# Do we have a logger?
	def have_logger?
		defined?(@@logger) and ! @@logger.nil?
	end

	# Try to acquire a lock using SQL UPDATE. Returns true if successfully acquired.
	def acquire_lock
		@@logger.info { "Acquiring a lock in the database." } if have_logger?
		Tournament.dataset.filter(:id => self.id, :locked => false).update(:locked => true) != 0
	end

	# Try to return the lock using SQL UPDATE. Returns true if successfully returned (this should always return true,
	# unless we screw it up very bad)
	def return_lock
		@@logger.info { "Returning the lock to the database." } if have_logger?
		Tournament.dataset.filter(:id => self.id, :locked => true).update(:locked => false) != 0
	end

	# Are we locked?
	def locked?
		@@logger.info { "Checking if we are locked." } if have_logger?
		Tournament.dataset.filter(:id => self.id).first.locked
	end

	# Validating our model before continuing
	def validate
		@@logger.info { "Validating Tournament." } if have_logger?
		errors.add(:n_players, "can't be empty") if self.n_players.nil?
	end

	# #before_save hook. We'll use it to calculate the tournament data
	def before_save
		@@logger.info { "Inside #before_save hook." } if have_logger?
		super
		self.additional_rounds = 0 if self.additional_rounds.nil?
		self.rounds = (Math.log(self.n_players) / Math.log(2)).ceil + self.additional_rounds.abs
		self.matches_per_round = (self.n_players/2).floor
	end

	# Get the tie-breaking criteria
	#
	# (If not set by #criteria=, should be equal to [ :score, :buchholz_score, :neustadtl_score, :c_score, :opp_c_score, :wins ])
	def criteria
		if @criteria.nil?
			[ :score, :buchholz_score, :neustadtl_score, :c_score, :opp_c_score, :wins ]
		else
			@criteria
		end
	end

	# Inject the players for this tournament
	#
	# array:: an array of player ids. There shouldn't be repeated ids and there should be the exact number matching :n_players
	def inject_players(array)
		raise DiscrepantNumberOfPlayers if array.length != self.n_players
		raise RepeatedPlayerIds if array.uniq.sort != array.sort

		@@logger.info { "Injecting players" } if have_logger?
		array.each { |player_id|
			player = Player.create(:tournament => self, :in_tournament_id => player_id)
			player.save
		}
	end

	# Retrieve a table of players
	#
	# ordering:: one of 
	# 	:raw				- delivers in the order given by the database query
	# 	:random			- shuffle the resulting array before returning
	#		:criteria		- order by criteria (see #criteria)
	#		:score			- order by score
	#		:soft				- same as :score (just kept for compatibility)
	#		:hard				- order by score but shuffle every bracket (where "bracket" is a group with the same score)
	def players(ordering = :raw)
		@@logger.info { "Retrieving players." } if have_logger?
		myplayers = Player.dataset.filter(:tournament_id => self.id).all
		case ordering
			when :random then
				@@logger.info { "Ordering players: :random." } if have_logger?
				myplayers.shuffle
			when :criteria then
				@@logger.info { "Ordering players: :criteria." } if have_logger?
				myplayers.sort do |a, b|
					a_side = []
					b_side = []
					self.criteria.each do |func|
						a_side << a.send(func)
						b_side << b.send(func)
					end
					b_side <=> a_side
				end
			when :score, :soft then
				@@logger.info { "Ordering players: :score or :soft." } if have_logger?
				myplayers.sort { |a, b| b.score <=> a.score }
			when :hard then
				@@logger.info { "Ordering players: :hard." } if have_logger?
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
				@@logger.info { "Ordering players: :raw or any other thing." } if have_logger?
				myplayers
		end
	end

	# Array of player ids in the database (not in_tournament_ids)
	def player_ids
		my_ids = []
		players.each { |player|
			my_ids << player.id
		}
		return my_ids
	end

	# Has the tournament ended?
	def ended?
		self.round >= self.rounds and checkedout_matches.empty? and available_matches.empty?
	end

	# All matches from this tournament
	def all_matches
		@@logger.info { "Retrieving all matches." } if have_logger?
		Match.dataset.filter(:tournament_id => self.id).all
	end

	# Matches that already have a result
	def committed_matches
		@@logger.info { "Retrieving matches that already were decided." } if have_logger?
		Match.dataset.filter(:tournament_id => self.id).filter(:result => [-1, 0, 1]).all
	end

	# Matches that were checkedout but have not yet being committed
	def checkedout_matches
		@@logger.info { "Retrieving checkedout and undecided matches." } if have_logger?
		Match.dataset.filter(:tournament_id => self.id).filter(:result => nil).filter(:checked_out => true).all
	end

	# Matches that doesn't have a result and were not checked-out yet
	def available_matches
		@@logger.info { "Retrieving not checkedout and undecided matches." } if have_logger?
		Match.dataset.filter(:tournament_id => self.id).filter(:result => nil).filter(:checked_out => false).filter(:planned => false).all
	end

	# Number of matches that were repeated
	def repeated_matches
		@@logger.info { "Retrieving repeated matches." } if have_logger?
		Match.dataset.filter(:tournament_id => self.id).filter(:repeated => true).all.length
	end

	# Matches for a given round
	def round_matches(round)
		@@logger.info { "Retrieving matches for a given round." } if have_logger?
		Match.dataset.filter(:tournament_id => self.id).filter(:round => round).all
	end

	# Matches in planning stage
	def planned_matches(round)
		@@logger.info { "Retrieving planned matches." } if have_logger?
		Match.dataset.filter(:tournament_id => self.id).filter(:round => round).filter(:planned => true).all
	end

	# Checkout a match
	#
	# This uses SQL UPDATE and the column :checked_out as a way to "get a lock" in the database and
	# assure that the same match is not given twice.
	def checkout_match
		# First get a not-checked-out match out of the database
		@@logger.info { "Retrieving the first not-yet-checked-out match." } if have_logger?
		mymatch = Match[:tournament_id => self.id, :result => nil, :checked_out => false, :planned => false]
		if mymatch
			# If we can get one try to mark it as checked_out
			@@logger.info { "Trying to update it to :checked_out => true, so nobody gets it also." } if have_logger?
			if Match.dataset.filter(:id=>mymatch[:id], :checked_out => false).update(:checked_out=>true) != 0
				# Great! We've got it! Let's just change the object accordingly and return it.
				@@logger.info { "Success!" } if have_logger?
				mymatch.values[:checked_out] = true
				return mymatch
			else
				# Oops... some one was quickier. Let's try it again.
				@@logger.info { "Fail. Let's try again." } if have_logger?
				return checkout_match
			end
		else
			# There's no not-checked-out match left. Let's generate the next round and try again.
			@@logger.info { "There's no not-yet-checked-out matches left. We'll generate a new round." } if have_logger?
			gen_next_round
			@@logger.info { "New round generated. Let's try again." } if have_logger?
			return checkout_match
		end
	end

	# Commit a match. This will control not-checked-out matches.
	#
	# match:: either a Match object or an array in the format [p1_in_tournament_id, p2_in_tournament_id, result]
	def commit_match(match)
		if match.class == Array
			p1 = Player[:in_tournament_id => match[0], :tournament_id => self.id]
			p2 = Player[:in_tournament_id => match[1], :tournament_id => self.id]
			result = match[2]
		else
			p1 = match.p1
			p2 = match.p2
			result = match.result
		end
		@@logger.info { "Trying to find-out if this match were given and was not returned yet." } if have_logger?
		mymatch = RSwiss::Match[:p1_id => p1.id, :p2_id => p2.id, :checked_out => true, :result => nil]
		mymatch = RSwiss::Match[:p1_id => p2.id, :p2_id => p1.id, :checked_out => true, :result => nil] if mymatch.nil?
		raise MatchNotCheckedOut if mymatch.nil?
		@@logger.info { "Great... we found it. Let's commit it then." } if have_logger?
		mymatch.result = result
		mymatch.save
	end

	# Do we have this match? (both p1 x p2 and p2 x p1 returns true)
	#
	# p1: Player 1
	# p2: Player 2
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

		@@logger.info { "Deciding who is the winner." } if have_logger?
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
		@@logger.info { "We got a tie!" } if have_logger?
		raise StillTied
	end

	private

	# Generate the next round of matches
	def gen_next_round
		raise MatchesToBeCommitted.new(checkedout_matches.length) unless checkedout_matches.empty?
		raise EndOfTournament if ended?

		@@logger.info { "Acquiring the lock." } if have_logger?
		raise GeneratingRound unless self.acquire_lock

		@@logger.info { "Generating next round." } if have_logger?

		begin
			myplayers = self.round == 0 ? players(:random) : players(:soft) # round 0 is random

			@@logger.info { "Solving the bye first of all." } if have_logger?
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
			@@logger.info { "Generating the prospective matches." } if have_logger?
			gen_matches(myplayers, self.round)

			# Oops... not enough matches. We'll try to traverse the match array to find
			# some to delete and regenerate the round only with the last players shuffled.
			if self.matches_per_round != round_matches(self.round).length
				@@logger.info { "We haven't got enough matches. Trying to backtrack until solved." } if have_logger?
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
				@@logger.info { "We still haven't got enough matches. Trying hard rearrangements." } if have_logger?
				planned_matches(self.round).each { |match| match.delete }
				self.n_players.times { |n|
					@@logger.info { "Trying hard rearrangement ##{n}." } if have_logger?
					myplayers = players(:hard)
					gen_matches(myplayers, self.round)
					break if self.matches_per_round == round_matches(self.round).length # try no more if ok.
				}
			end

			# Argh! Still haven't reached the target!
			if self.matches_per_round != round_matches(self.round).length
				# We'll try repeating matches
				@@logger.info { "We still haven't got enough matches. Trying repetition, if allowed." } if have_logger?
				if self.allow_repeat
					gen_matches(myplayers, self.round, true)
				else
					raise SSWiss::MaxRearranges
				end
			end

			# Well... that's all folks
			raise RSwiss::RepetitionExhausted if self.matches_per_round != round_matches(self.round).length

			# Great... we have generated enough matches for this round.
			# Turn the planned flag off
			@@logger.info { "Turning :planned flag off." } if have_logger?
			planned_matches(self.round).each { |match| match.planned = false; match.save }
			# And save the tournament state
			self.round += 1
			self.save
		ensure
			@@logger.info { "Returning the lock." } if have_logger?
			self.return_lock
		end
	end

	# Generate matches inside a round (this is auxiliary function to #gen_next_round)
	def gen_matches(myplayers, round, repeat_on = false)
		@@logger.info { "Generating matches." } if have_logger?
		myplayers.each do |p1|
			next if p1.matches != round                 # exceeded number of matches in a round
			opponents_of_p1 = p1.opponents
			myplayers.each do |p2|
				myrepeated = false
				next if p1 == p2                          # player cannot play against itself
				next if p2.matches != round               # exceeded number of matches in a round (e.g.: received a bye already)
				if opponents_of_p1.include?(p2)           # cannot repeat...
					next unless repeat_on                   # ... unless they told us so
					@@logger.info { "Deciding on repetition." } if have_logger?
					m = RSwiss::Match[:p1_id => p1.id, :p2_id => p2.id]
					m = RSwiss::Match[:p1_id => p2.id, :p2_id => p1.id] if m.nil?
					next if m.repeated                      # ... and it was not repeated before
					m.repeated = true
					m.save
					myrepeated = true
				end
				m = Match.create(:p1 => p1, :p2 => p2, :tournament => self, :round => round, :repeated => myrepeated)
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

	def Player.logger=(logger)
		@@logger = logger
	end

	def have_logger?
		defined?(@@logger) and ! @@logger.nil?
	end

	# :nodoc:
	def inspect
		sprintf("#<%s:%#x id=%d in_tournament_id=%d matches=%d byed=%s score=%.1f buchholz_score=%.1f c_score=%.1f opp_c_score=%.1f wins=%d, neustadtl_score=%.2f>", self.class.name, self.__id__.abs, self.id, self.in_tournament_id, matches, byed.inspect, score, buchholz_score, c_score, opp_c_score, wins, neustadtl_score)
	end

	def validate
		@@logger.info { "Validating Player" } if have_logger?
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

	def Match.logger=(logger)
		@@logger = logger
	end

	def have_logger?
		defined?(@@logger) and ! @@logger.nil?
	end

	many_to_one :p1
	many_to_one :p2
	many_to_one :tournament

	# :nodoc:
	def inspect
		sprintf("#<%s:%#x id=%d p1_id=%d p2_id=%d round=%d result=%s planned=%s repeated=%s>", self.class.name, self.__id__.abs, self.id, self.p1.id, self.p2.id, self.round, self.result.inspect, self.planned.inspect, self.repeated.inspect)
	end

	def validate
		@@logger.info { "Validating Match" } if have_logger?
		errors.add(:p1_id, "can't be empty") if self.p1.nil?
		errors.add(:p2_id, "can't be empty") if self.p2.nil?
		errors.add(:tournament, "can't be empty") if self.tournament.nil?
		errors.add(:p1_id, "can't be equal to :p2_id") if self.p1 == self.p2
	end

end # of class Match

# Tournament Exceptions
class RepeatedPlayerIds < Exception
	def faultCode; 101; end; def message; "Repeated player ids detected!"; end
end
class DiscrepantNumberOfPlayers < Exception
	def faultCode; 102; end; def message; "The length of the provided array must match :n_players"; end
end
class MatchesToBeCommitted < Exception
	def initialize(n); @n = n; end; def faultCode; 201; end
	def message;
		"Still #{@n} matches to be returned!"
	end
end
class EndOfTournament < Exception
	def faultCode; 202; end; def message; "This tournament reached the end!"; end
end
class GeneratingRound < Exception
	def faultCode; 203; end; def message; "Please wait while we generate the next round."; end
end
class MaxRearranges < Exception
	def faultCode; 204; end; def message; "Reached maximum number of rearrangements allowed."; end
end
class RepetitionExhausted < Exception
	def faultCode; 205; end; def message; "Allowing match repetition as last resort was not enough."; end
end
class MatchNotCheckedOut < Exception
	def faultCode; 303; end; def message; "This match has not been checked out!"; end
end
class StillRunning < Exception
	def faultCode; 401; end; def message; "The Tournament has not ended yet."; end
end
class StillTied < Exception
	def faultCode; 402; end; def message; "We have a difficult tie to break. Try flipping a coin."; end
end

end # of module RSwiss

