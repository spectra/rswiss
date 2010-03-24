# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 43):
# <pablo@propus.com.br> wrote this file and it's provided AS-IS, no
# warranties. As long as you retain this notice you can do whatever you
# want with this stuff. If we meet some day, and you think this stuff is
# worth it, you can buy me a beer in return."
# ----------------------------------------------------------------------
require 'sequel/extensions/migration'
require 'data/models'

class BaseSchema < Sequel::Migration
	def up
		create_table! :tournaments do
			primary_key :id
			boolean :allow_repeat, :default => false
			Fixnum :n_players
			Fixnum :rounds
			Fixnum :matches_per_round
			Fixnum :additional_rounds
			Fixnum :round, :default => 0
		end

		create_table! :players do
			primary_key :id
			Fixnum :in_tournament_id
			boolean :byed, :default => false
			foreign_key :tournament_id, :tournaments
			Fixnum :matches, :default => 0
		end

		create_table! :matches do
			primary_key :id
			foreign_key :p1_id, :players
			foreign_key :p2_id, :players
			foreign_key :tournament_id, :tournaments
			Fixnum :result
			boolean :checked_out, :default => false
			boolean :repeated, :default => false
			boolean :planned, :default => true
			Fixnum :round
		end
	end

	def down
		drop_table :tournaments
		drop_table :players
		drop_table :matches
	end
end
