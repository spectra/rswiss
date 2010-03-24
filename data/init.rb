# ----------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 43):
# <pablo@propus.com.br> wrote this file and it's provided AS-IS, no
# warranties. As long as you retain this notice you can do whatever you
# want with this stuff. If we meet some day, and you think this stuff is
# worth it, you can buy me a beer in return."
# ----------------------------------------------------------------------

require 'sequel'
require 'yaml'

content = File.new("config/database.yml").read
settings = YAML::load content
DB = Sequel.connect settings["connector"]

require 'data/models'
