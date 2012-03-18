module ActiveSupport
  # A class with no predefined methods that behaves similarly to Builder's
  # BlankSlate. Used for proxy classes.
  class BasicObject < ::BasicObject
    undef_method :==
    undef_method :equal?

    # Let ActiveSupport::BasicObject at least raise exceptions.
    def raise(*args)
      ::Object.send(:raise, *args)
    end
  end
end
