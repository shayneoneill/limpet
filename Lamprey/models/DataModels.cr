require "active_record"
require "sqlite_adapter"

class Route < ActiveRecord::Model

  adapter sqlite

  primary id     : Int
  field regex    : String
  field did_id   : Int
  field trunk_id : Int

end

class Registration < ActiveRecord::Model

  adapter sqlite

  prinary id     : Int
  field username : String
  field number   : String
  field password : String
  field address  : String
  field local   : Boolean

end
