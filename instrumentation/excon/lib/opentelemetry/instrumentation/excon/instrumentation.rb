# frozen_string_literal: true

# Copyright 2020 OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module Instrumentation
    module Excon
      # The Instrumentation class contains logic to detect and install the Excon
      # instrumentation instrumentation
      class Instrumentation < OpenTelemetry::Instrumentation::Base
        install do |_config|
          require_dependencies
          add_middleware
        end

        present do
          defined?(::Excon)
        end

        private

        def require_dependencies
          require_relative 'middlewares/tracer_middleware'
        end

        def add_middleware
          ::Excon.defaults[:middlewares] =
            Middlewares::TracerMiddleware.around_default_stack
        end
      end
    end
  end
end
