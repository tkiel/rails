# frozen_string_literal: true

class ActiveStorage::Identification
  attr_reader :blob

  def initialize(blob)
    @blob = blob
  end

  def apply
    blob.update!(content_type: content_type, identified: true) unless blob.identified?
  end

  private
    def content_type
      Marcel::MimeType.for(identifiable_chunk, name: filename, declared_type: declared_content_type)
    end


    def identifiable_chunk
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |client|
        client.get(uri, "Range" => "0-4096").body
      end
    end

    def uri
      @uri ||= URI.parse(blob.service_url)
    end


    def filename
      blob.filename.to_s
    end

    def declared_content_type
      blob.content_type
    end
end
