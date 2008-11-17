require 'rubygems'
require 'dm-core'
DataMapper.setup(:default, "sqlite3:///#{Dir.pwd}/db/dev.db")
class Link
    include DataMapper::Resource
    property  :id,       Integer, :serial => true
    property  :url,      String
    property  :tag,      String
end
