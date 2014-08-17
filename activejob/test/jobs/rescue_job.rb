class RescueJob < ActiveJob::Base
  class OtherError < StandardError; end

  rescue_from(ArgumentError) do
    JobBuffer.add('rescued from ArgumentError')
    arguments[0] = "DIFFERENT!"
    retry_now
  end

  rescue_from(ActiveJob::DeserializationError) do |e|
    JobBuffer.add('rescued from DeserializationError')
    JobBuffer.add("DeserializationError original exception was #{e.original_exception.class.name}")
  end

  def perform(person = "david")
    case person
    when "david"
      raise ArgumentError, "Hair too good"
    when "other"
      raise OtherError
    else
      JobBuffer.add('performed beautifully')
    end
  end
end
