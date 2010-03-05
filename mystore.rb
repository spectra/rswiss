# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 43):
# <pablo@propus.com.br> wrote this file and it's provided AS-IS, no
# warranties. As long as you retain this notice you can do whatever you
# want with this stuff. If we meet some day, and you think this stuff is
# worth it, you can buy me a beer in return."
# ----------------------------------------------------------------------

require 'thread'
require 'fileutils'
require 'tmpdir'

# Simple store with delayed writing.
class MyStore
	attr_reader :file

	# Initializes a new store.
	# If both interval and operations are 0, it will never write to file!
	# If both are non-zero, we'll honor what happens first.
	#
	# file:: file where we're suppose to write
	# interval:: number of seconds between writes (default: 10)
	# operations:: number of operations before writing (default 0: means just consider time)
	def initialize(file, interval = 10, operations = 0)
		@file = file
		@backup = file + "~"
		@temp = Dir::tmpdir + "/MyStore.#{$$}.~~~"
		@interval = interval
		@operations = @counter = operations
		@mutex = Mutex.new
		@hash = File.exists?(@file) ? Marshal.load(File.read(@file)) : Hash.new
		@last_saved = Time.now
		@thread = start_thread
		@changed = true
	end

	# Anything we don't know about, just pass along the internal hash.
	def method_missing(sym, *args, &block)
		@hash.send(sym, *args, &block)
	end

	# Start a new transaction
	#
	# flag:: if true, the transaction is readonly (doesn't not count as operation)
	def transaction(flag = false, &block)
		block.call
		@changed = flag ? false : true
		decrease_counter unless flag
	end

	# Save the state to the file, keeping a backup. This operation is protected by a Mutex.
	def save!
		return unless @changed
		@mutex.synchronize {
			FileUtils::cp(@file, @backup) unless ! File.exists?(@file)
			File.open(@temp, "w+") { |f|
				f.write(Marshal.dump(@hash))
			}
			FileUtils::cp(@temp, @file)
			@last_saved = Time.now
			@changed = false
		}
	end

	private

	# Start the thread
	def start_thread
		Thread.new { loop {
			sleep 1 while @interval <= 0
			sleep 1 while (@last_saved + @interval) > Time.now
			save!
		} }
	end

	# Decrease the operation counter (and take adequate actions).
	def decrease_counter
		return if @operations == 0
		@counter -= 1
		if @counter == 0
			save!
			@counter = @operations
		end
	end

end

