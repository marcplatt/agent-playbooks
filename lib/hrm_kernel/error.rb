# frozen_string_literal: true

module HrmKernel
  class Error < StandardError
    attr_reader :code, :details

    def initialize(code_or_message = "kernel error", message = nil, details: nil)
      if message.nil?
        @code = "kernel_error"
        message = code_or_message.to_s
      else
        @code = code_or_message.to_s
      end
      @details = details
      super(message)
    end
  end
end
