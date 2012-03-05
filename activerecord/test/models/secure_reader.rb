class SecureReader < ActiveRecord::Base
  self.table_name = "readers"

  belongs_to :secure_post, :class_name => "Post", :foreign_key => "post_id"
  belongs_to :secure_person, :inverse_of => :secure_readers, :class_name => "Person", :foreign_key => "person_id"


  attr_accessible nil
end
