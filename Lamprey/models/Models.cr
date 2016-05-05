require "active_record"
require "sqlite_adapter"

class Route < ActiveRecord::Model

  adapter sqlite

  primary id     : Int
  field regex    : String
  field did_id   : Int
  field trunk_id : Int

end
