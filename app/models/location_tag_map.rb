class LocationTagMap < ActiveRecord::Base
  set_table_name "location_tag_map"
  set_primary_key "location_tag_id, location_id"
end
