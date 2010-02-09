# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 43):
# <pablo@propus.com.br> wrote this file and it's provided AS-IS, no
# warranties. As long as you retain this notice you can do whatever you
# want with this stuff. If we meet some day, and you think this stuff is
# worth it, you can buy me a beer in return."
# ----------------------------------------------------------------------
require 'xmlrpc/server'
require 'rack'
require 'rack/request'
require 'rack/response'

module Rack
	class XMLRPCServer < XMLRPC::BasicServer
		def initialize(*args)
			super(*args)
		end

		def call(env)
			request = Rack::Request.new(env)
			return [ 405, {}, "Method Not Allowed" ]    unless request.post?
			return [ 400, {}, "Bad Request" ]           unless parse_content_type(request.content_type).first == "text/xml"

			length = request.content_length.to_i
			return [ 411, {}, "Length Required" ]       unless length > 0

			data = request.body
			return [ 400, {}, "Bad Request" ]           if data.nil? or data.size != length

			data_str = data.read(length)
			resp = process(data_str)
			return [ 500, {}, "Internal Server Error" ] if resp.nil? or resp.size <= 0

			response = Rack::Response.new
			response.write resp
			response["Content-Type"] = "text/xml; charset=utf-8"
			response.finish
		end

	end # of class XMLRPC
end # of module Rack
