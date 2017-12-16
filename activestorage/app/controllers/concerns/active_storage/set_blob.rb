# frozen_string_literal: true

module ActiveStorage::SetBlob
  extend ActiveSupport::Concern

  included do
    before_action :set_blob
  end

  private
    def set_blob
      @blob = ActiveStorage::Blob.find_signed(params[:signed_blob_id] || params[:signed_id])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      head :not_found
    end
end
