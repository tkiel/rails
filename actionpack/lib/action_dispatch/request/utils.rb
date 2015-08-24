module ActionDispatch
  class Request < Rack::Request
    class Utils # :nodoc:

      mattr_accessor :perform_deep_munge
      self.perform_deep_munge = true

      def self.normalize_encode_params(params)
        if perform_deep_munge
          NoNilParamEncoder.normalize_encode_params params
        else
          ParamEncoder.normalize_encode_params params
        end
      end

      class ParamEncoder # :nodoc:
        # Convert nested Hash to HashWithIndifferentAccess.
        #
        def self.normalize_encode_params(params)
          case params
          when Array
            handle_array params
          when Hash
            if params.has_key?(:tempfile)
              ActionDispatch::Http::UploadedFile.new(params)
            else
              params.each_with_object({}) do |(key, val), new_hash|
                new_hash[key] = normalize_encode_params(val)
              end.with_indifferent_access
            end
          else
            params
          end
        end

        def self.handle_array(params)
          params.map! { |el| normalize_encode_params(el) }
        end
      end

      # Remove nils from the params hash
      class NoNilParamEncoder < ParamEncoder # :nodoc:
        def self.handle_array(params)
          list = super
          list.compact!
          list
        end
      end
    end
  end
end

