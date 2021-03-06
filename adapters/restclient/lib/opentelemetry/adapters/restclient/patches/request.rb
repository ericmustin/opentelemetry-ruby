# frozen_string_literal: true

# Copyright 2020 OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module Adapters
    module RestClient
      module Patches
        # Module to prepend to RestClient::Request for instrumentation
        module Request
          def execute(&block)
            trace_request do |_span|
              super(&block)
            end
          end

          private

          def trace_request # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
            http_method = method.upcase
            span = tracer.start_span(
              "HTTP #{http_method}",
              attributes: {
                'http.method' => http_method,
                'http.url' => url
              },
              kind: :client
            )

            tracer.with_span(span) do
              OpenTelemetry.propagation.http.inject(processed_headers)
            end

            yield(span).tap do |response|
              # Verify return value is a response.
              # If so, add additional attributes.
              if response.is_a?(::RestClient::Response)
                span.set_attribute('http.status_code', response.code)
                span.set_attribute('http.status_text', ::RestClient::STATUSES[response.code])
                span.status = OpenTelemetry::Trace::Status.http_to_status(
                  response.code
                )
              end
            end
          rescue ::RestClient::ExceptionWithResponse => e
            span.set_attribute('http.status_code', e.http_code)
            span.status = OpenTelemetry::Trace::Status.http_to_status(
              e.http_code
            )

            raise e
          ensure
            span.finish
          end

          def tracer
            RestClient::Adapter.instance.tracer
          end
        end
      end
    end
  end
end
