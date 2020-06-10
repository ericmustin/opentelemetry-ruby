# frozen_string_literal: true

# Copyright 2019 OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'ddtrace/span'
require 'ddtrace/ext/http'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/redis/ext'
require 'opentelemetry/trace/status'

module OpenTelemetry
  module Exporters
    module Datadog
      class Exporter
        # @api private
        class SpanEncoder
          DD_ORIGIN = "_dd_origin"
          AUTO_REJECT = 0
          AUTO_KEEP = 1
          USER_KEEP = 2
          SAMPLE_RATE_METRIC_KEY = "_sample_rate"
          SAMPLING_PRIORITY_KEY = "_sampling_priority_v1"

          INSTRUMENTATION_SPAN_TYPES = {
            "OpenTelemetry::Adapters::Ethon": ::Datadog::Ext::HTTP::TYPE_OUTBOUND,
            "OpenTelemetry::Adapters::Excon": ::Datadog::Ext::HTTP::TYPE_OUTBOUND,
            "OpenTelemetry::Adapters::Faraday": ::Datadog::Ext::HTTP::TYPE_OUTBOUND,
            "OpenTelemetry::Adapters::Net::HTTP": ::Datadog::Ext::HTTP::TYPE_OUTBOUND,
            "OpenTelemetry::Adapters::Rack": ::Datadog::Ext::HTTP::TYPE_INBOUND,
            "OpenTelemetry::Adapters::Redis": ::Datadog::Contrib::Redis::Ext::TYPE,
            "OpenTelemetry::Adapters::RestClient": ::Datadog::Ext::HTTP::TYPE_OUTBOUND,
            "OpenTelemetry::Adapters::Sidekiq": ::Datadog::Ext::AppTypes::WORKER,
            "OpenTelemetry::Adapters::Sinatra": ::Datadog::Ext::HTTP::TYPE_INBOUND
          }

          def translate_to_datadog(otel_spans, service) # rubocop:disable Metrics/AbcSize
            datadog_spans = []

            otel_spans.each do |span|
              trace_id, span_id, parent_id = get_trace_ids(span)
              span_type = get_span_type(span)

              datadog_span = ::Datadog::Span.new(nil, span.name, {
                service: service, 
                trace_id: trace_id,
                parent_id: parent_id,
                resource: span.name,
                span_type: span_type
              })

              # span_id is autogenerated so have to override
              datadog_span.span_id = span_id

              datadog_span.start_time = span.start_timestamp
              datadog_span.end_time = span.end_timestamp

              # set span.error, span tag error.msg/error.type
              if span.status && span.status.canonical_code != OpenTelemetry::Trace::Status::OK
                datadog_span.error = 1

                if span.status.description
                  exception_value, exception_type = get_exception_info(span)

                  datadog_span.set_tag("error.msg", exception_value)
                  datadog_span.set_tag("error.type", exception_type)
                end
              end
              
              #set tags
              if span.attributes
                span.attributes.keys.each do |attribute|

                  datadog_span.set_tag(attribute, span.attributes[attribute])
                end
              end

              # TODO: serialized span data does not contain tracestate info
              # add origin to root span
              origin = get_origin(span)
              if origin && parent_id == 0
                  datadog_span.set_tag(DD_ORIGIN, origin)
              end

              # TODO: serialized span data does not contain sampling rate info
              # define sampling rate metric
              # In other languages, spans that aren't sampled don't get passed to on_finish
              # Is this the case with ruby?
              sampling_rate = get_sampling_rate(span)

              if sampling_rate
                datadog_span.set_metric(SAMPLE_RATE_METRIC_KEY, sampling_rate)
              end

              datadog_spans << datadog_span
            end

            datadog_spans
          end

          private

          def get_trace_ids(span)
            trace_id = int64(span.trace_id[0,16])
            span_id = int64(span.span_id)
            parent_id = int64(span.parent_span_id)

            [trace_id, span_id, parent_id]
          end

          def get_span_type(span)
            # Get Datadog span type
            if span.instrumentation_library
              instrumentation_name = span.instrumentation_library.name
              INSTRUMENTATION_SPAN_TYPES[instrumentation_name]
            end
          end

          def get_exc_info(span)
            # Parse span status description for exception type and value
            exc_value, exc_type = span.status.description.split(":", 2)

            exc_type = "" if exc_type.nil?

            [exc_value, exc_type.strip]
          end

          def get_origin(span)
            # TODO: expose tracestate to the SpanData struct
            # struct throws NameError on missing member
            begin
              if span[:tracestate]
                span.tracestate.get(DD_ORIGIN)
              end
            rescue NameError
              ""
            end
          end

          def get_sampling_rate(span)
            if span.trace_flags && span.trace_flags.sampled?
              # TODO: expose probability sampling rate of active tracer in SpanData
              # tenatively it would be in tracestate?
              1
            else
              0
            end
          end

          def int64(hex_string)
            int = hex_string.to_i(16)
            output = int < (1 << 63) ? int : int - (1 << 64)

            # from: https://github.com/DataDog/dd-trace-rb/blob/e28889d4fa4aaa8cc134c0bcaaeeb31946b12eac/lib/ddtrace/distributed_tracing/headers/headers.rb#L39
            output < 0 ? output + (2**64) : output
          end
        end
      end
    end
  end
end