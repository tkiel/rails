# frozen_string_literal: true

# The base class for all Active Storage controllers.
class ActiveStorage::BaseController < ActionController::Base
  include ActiveStorage::SetCurrent

  protect_from_forgery with: :exception
end
