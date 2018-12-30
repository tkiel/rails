# frozen_string_literal: true

require "active_storage/downloader"

# A blob is a record that contains the metadata about a file and a key for where that file resides on the service.
# Blobs can be created in two ways:
#
# 1. Subsequent to the file being uploaded server-side to the service via <tt>create_after_upload!</tt>.
# 2. Ahead of the file being directly uploaded client-side to the service via <tt>create_before_direct_upload!</tt>.
#
# The first option doesn't require any client-side JavaScript integration, and can be used by any other back-end
# service that deals with files. The second option is faster, since you're not using your own server as a staging
# point for uploads, and can work with deployments like Heroku that do not provide large amounts of disk space.
#
# Blobs are intended to be immutable in as-so-far as their reference to a specific file goes. You're allowed to
# update a blob's metadata on a subsequent pass, but you should not update the key or change the uploaded file.
# If you need to create a derivative or otherwise change the blob, simply create a new blob and purge the old one.
class ActiveStorage::Blob < ActiveRecord::Base
  require_dependency "active_storage/blob/analyzable"
  require_dependency "active_storage/blob/identifiable"
  require_dependency "active_storage/blob/representable"

  include Analyzable
  include Identifiable
  include Representable

  self.table_name = "active_storage_blobs"

  has_secure_token :key
  store :metadata, accessors: [ :analyzed, :identified ], coder: ActiveRecord::Coders::JSON

  class_attribute :service

  has_many :attachments

  scope :unattached, -> { left_joins(:attachments).where(ActiveStorage::Attachment.table_name => { blob_id: nil }) }

  before_destroy(prepend: true) do
    raise ActiveRecord::InvalidForeignKey if attachments.exists?
  end

  class << self
    # You can use the signed ID of a blob to refer to it on the client side without fear of tampering.
    # This is particularly helpful for direct uploads where the client-side needs to refer to the blob
    # that was created ahead of the upload itself on form submission.
    #
    # The signed ID is also used to create stable URLs for the blob through the BlobsController.
    def find_signed(id)
      find ActiveStorage.verifier.verify(id, purpose: :blob_id)
    end

    # Returns a new, unsaved blob instance after the +io+ has been uploaded to the service.
    # When providing a content type, pass <tt>identify: false</tt> to bypass automatic content type inference.
    def build_after_upload(io:, filename:, content_type: nil, metadata: nil, identify: true)
      new(filename: filename, content_type: content_type, metadata: metadata).tap do |blob|
        blob.upload(io, identify: identify)
      end
    end

    def build_after_unfurling(io:, filename:, content_type: nil, metadata: nil, identify: true) #:nodoc:
      new(filename: filename, content_type: content_type, metadata: metadata).tap do |blob|
        blob.unfurl(io, identify: identify)
      end
    end

    # Returns a saved blob instance after the +io+ has been uploaded to the service. Note, the blob is first built,
    # then the +io+ is uploaded, then the blob is saved. This is done this way to avoid uploading (which may take
    # time), while having an open database transaction.
    # When providing a content type, pass <tt>identify: false</tt> to bypass automatic content type inference.
    def create_after_upload!(io:, filename:, content_type: nil, metadata: nil, identify: true)
      build_after_upload(io: io, filename: filename, content_type: content_type, metadata: metadata, identify: identify).tap(&:save!)
    end

    # Returns a saved blob _without_ uploading a file to the service. This blob will point to a key where there is
    # no file yet. It's intended to be used together with a client-side upload, which will first create the blob
    # in order to produce the signed URL for uploading. This signed URL points to the key generated by the blob.
    # Once the form using the direct upload is submitted, the blob can be associated with the right record using
    # the signed ID.
    def create_before_direct_upload!(filename:, byte_size:, checksum:, content_type: nil, metadata: nil)
      create! filename: filename, byte_size: byte_size, checksum: checksum, content_type: content_type, metadata: metadata
    end

    # To prevent problems with case-insensitive filesystems, especially in combination
    # with databases which treat indices as case-sensitive, all blob keys generated are going
    # to only contain the base-36 character alphabet and will therefore be lowercase. To maintain
    # the same or higher amount of entropy as in the base-58 encoding used by `has_secure_token`
    # the number of bytes used is increased to 28 from the standard 24
    def generate_unique_secure_token
      SecureRandom.base36(28)
    end
  end

  # Returns a signed ID for this blob that's suitable for reference on the client-side without fear of tampering.
  # It uses the framework-wide verifier on <tt>ActiveStorage.verifier</tt>, but with a dedicated purpose.
  def signed_id
    ActiveStorage.verifier.generate(id, purpose: :blob_id)
  end

  # Returns the key pointing to the file on the service that's associated with this blob. The key is the
  # secure-token format from Rails in lower case. So it'll look like: xtapjjcjiudrlk3tmwyjgpuobabd.
  # This key is not intended to be revealed directly to the user.
  # Always refer to blobs using the signed_id or a verified form of the key.
  def key
    # We can't wait until the record is first saved to have a key for it
    self[:key] ||= self.class.generate_unique_secure_token
  end

  # Returns an ActiveStorage::Filename instance of the filename that can be
  # queried for basename, extension, and a sanitized version of the filename
  # that's safe to use in URLs.
  def filename
    ActiveStorage::Filename.new(self[:filename])
  end

  # Returns true if the content_type of this blob is in the image range, like image/png.
  def image?
    content_type.start_with?("image")
  end

  # Returns true if the content_type of this blob is in the audio range, like audio/mpeg.
  def audio?
    content_type.start_with?("audio")
  end

  # Returns true if the content_type of this blob is in the video range, like video/mp4.
  def video?
    content_type.start_with?("video")
  end

  # Returns true if the content_type of this blob is in the text range, like text/plain.
  def text?
    content_type.start_with?("text")
  end


  # Returns the URL of the blob on the service. This URL is intended to be short-lived for security and not used directly
  # with users. Instead, the +service_url+ should only be exposed as a redirect from a stable, possibly authenticated URL.
  # Hiding the +service_url+ behind a redirect also gives you the power to change services without updating all URLs. And
  # it allows permanent URLs that redirect to the +service_url+ to be cached in the view.
  def service_url(expires_in: ActiveStorage.service_urls_expire_in, disposition: :inline, filename: nil, **options)
    filename = ActiveStorage::Filename.wrap(filename || self.filename)

    service.url key, expires_in: expires_in, filename: filename, content_type: content_type_for_service_url,
      disposition: forced_disposition_for_service_url || disposition, **options
  end

  # Returns a URL that can be used to directly upload a file for this blob on the service. This URL is intended to be
  # short-lived for security and only generated on-demand by the client-side JavaScript responsible for doing the uploading.
  def service_url_for_direct_upload(expires_in: ActiveStorage.service_urls_expire_in)
    service.url_for_direct_upload key, expires_in: expires_in, content_type: content_type, content_length: byte_size, checksum: checksum
  end

  # Returns a Hash of headers for +service_url_for_direct_upload+ requests.
  def service_headers_for_direct_upload
    service.headers_for_direct_upload key, filename: filename, content_type: content_type, content_length: byte_size, checksum: checksum
  end


  # Uploads the +io+ to the service on the +key+ for this blob. Blobs are intended to be immutable, so you shouldn't be
  # using this method after a file has already been uploaded to fit with a blob. If you want to create a derivative blob,
  # you should instead simply create a new blob based on the old one.
  #
  # Prior to uploading, we compute the checksum, which is sent to the service for transit integrity validation. If the
  # checksum does not match what the service receives, an exception will be raised. We also measure the size of the +io+
  # and store that in +byte_size+ on the blob record. The content type is automatically extracted from the +io+ unless
  # you specify a +content_type+ and pass +identify+ as false.
  #
  # Normally, you do not have to call this method directly at all. Use the factory class methods of +build_after_upload+
  # and +create_after_upload!+.
  def upload(io, identify: true)
    unfurl io, identify: identify
    upload_without_unfurling io
  end

  def unfurl(io, identify: true) #:nodoc:
    self.checksum     = compute_checksum_in_chunks(io)
    self.content_type = extract_content_type(io) if content_type.nil? || identify
    self.byte_size    = io.size
    self.identified   = true
  end

  def upload_without_unfurling(io) #:nodoc:
    service.upload key, io, checksum: checksum, **service_metadata
  end

  # Downloads the file associated with this blob. If no block is given, the entire file is read into memory and returned.
  # That'll use a lot of RAM for very large files. If a block is given, then the download is streamed and yielded in chunks.
  def download(&block)
    service.download key, &block
  end

  # Downloads the blob to a tempfile on disk. Yields the tempfile.
  #
  # The tempfile's name is prefixed with +ActiveStorage-+ and the blob's ID. Its extension matches that of the blob.
  #
  # By default, the tempfile is created in <tt>Dir.tmpdir</tt>. Pass +tempdir:+ to create it in a different directory:
  #
  #   blob.open(tempdir: "/path/to/tmp") do |file|
  #     # ...
  #   end
  #
  # The tempfile is automatically closed and unlinked after the given block is executed.
  #
  # Raises ActiveStorage::IntegrityError if the downloaded data does not match the blob's checksum.
  def open(tempdir: nil, &block)
    ActiveStorage::Downloader.new(self, tempdir: tempdir).download_blob_to_tempfile(&block)
  end


  # Deletes the files on the service associated with the blob. This should only be done if the blob is going to be
  # deleted as well or you will essentially have a dead reference. It's recommended to use #purge and #purge_later
  # methods in most circumstances.
  def delete
    service.delete(key)
    service.delete_prefixed("variants/#{key}/") if image?
  end

  # Deletes the file on the service and then destroys the blob record. This is the recommended way to dispose of unwanted
  # blobs. Note, though, that deleting the file off the service will initiate a HTTP connection to the service, which may
  # be slow or prevented, so you should not use this method inside a transaction or in callbacks. Use #purge_later instead.
  def purge
    destroy
    delete
  rescue ActiveRecord::InvalidForeignKey
  end

  # Enqueues an ActiveStorage::PurgeJob to call #purge. This is the recommended way to purge blobs from a transaction,
  # an Active Record callback, or in any other real-time scenario.
  def purge_later
    ActiveStorage::PurgeJob.perform_later(self)
  end

  private
    def compute_checksum_in_chunks(io)
      Digest::MD5.new.tap do |checksum|
        while chunk = io.read(5.megabytes)
          checksum << chunk
        end

        io.rewind
      end.base64digest
    end

    def extract_content_type(io)
      Marcel::MimeType.for io, name: filename.to_s, declared_type: content_type
    end

    def forcibly_serve_as_binary?
      ActiveStorage.content_types_to_serve_as_binary.include?(content_type)
    end

    def allowed_inline?
      ActiveStorage.content_types_allowed_inline.include?(content_type)
    end

    def content_type_for_service_url
      forcibly_serve_as_binary? ? ActiveStorage.binary_content_type : content_type
    end

    def forced_disposition_for_service_url
      if forcibly_serve_as_binary? || !allowed_inline?
        :attachment
      end
    end

    def service_metadata
      if forcibly_serve_as_binary?
        { content_type: ActiveStorage.binary_content_type, disposition: :attachment, filename: filename }
      elsif !allowed_inline?
        { content_type: content_type, disposition: :attachment, filename: filename }
      else
        { content_type: content_type }
      end
    end

    ActiveSupport.run_load_hooks(:active_storage_blob, self)
end
