# frozen_string_literal: true

# Copyright 2020 OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module Instrumentation
    module RestClient
      # The Instrumentation class contains logic to detect and install the RestClient
      # instrumentation instrumentation
      class Instrumentation < OpenTelemetry::Instrumentation::BaseInstrumentation
        install do |_config|
          require_dependencies
          patch_request
        end

        present do
          defined?(::RestClient)
        end

        private

        def require_dependencies
          require_relative 'patches/request'
        end

        def patch_request
          ::RestClient::Request.prepend(Patches::Request)
        end
      end
    end
  end
end