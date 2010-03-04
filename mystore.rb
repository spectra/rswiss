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

class MyStore
	attr_accessor :interval
	attr_reader :file
	def initialize(file, interval = 10)
		@file = file
		@backup = file + "~"
		@temp = Dir::tmpdir + "/MyStore.#{$$}.~~~"
		@interval = interval
		@mutex = Mutex.new
		@hash = File.exists?(@file) ? Marshal.load(File.read(@file)) : Hash.new
		@last_saved = Time.now
		@thread = start_thread
	end

	def method_missing(sym, *args, &block)
		@hash.send(sym, *args, &block)
	end

	# Just for compatibility with PStore
	def transaction(flag = true, &block)
		block.call
	end

	def save!
		@mutex.synchronize {
			FileUtils::cp(@file, @backup) unless ! File.exists?(@file)
			File.open(@temp, "w+") { |f|
				f.write(Marshal.dump(@hash))
			}
			FileUtils::cp(@temp, @file)
			@last_saved = Time.now
		}
	end

	private

	def start_thread
		Thread.new {
			sleep 1 while (@last_saved + @interval) > Time.now
			save!
		}
	end

end

