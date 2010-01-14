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
