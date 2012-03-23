class Reply < ActiveRecord::Base
  scope :base, -> { scoped }
  belongs_to :topic, :include => [:replies]
  belongs_to :developer

  validates_presence_of :content
end
