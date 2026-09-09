# frozen_string_literal: true

require "digest"
require "json"
require "time"

require_relative "error"
require_relative "host"

module HrmKernel
  # Append-only technical observations asserted by a trusted local adapter.
  # These records are evidence for orchestration and never operator commands.
  class SupervisorInput
    SCHEMA_VERSION = "ap-hrm-supervisor-input/1"
    LEDGER_NAME = "supervisor-inputs.jsonl"
    MAX_RECORDS = 256
    MAX_LEDGER_BYTES = 512 * 1024
    MAX_LINE_BYTES = 16 * 1024
    MAX_UNREAD_BYTES = 48 * 1024
    MAX_SUMMARY_BYTES = 4096
    MAX_DETAIL_BYTES = 4096
    MAX_REFERENCE_BYTES = 1024
    MAX_FACTS = 12
    MAX_FACT_VALUE_BYTES = 1024
    COUNTERS = %w[input_tokens cached_input_tokens output_tokens reasoning_tokens total_tokens].freeze
    JOB_STATUSES = %w[running succeeded failed interrupted unknown].freeze
    KINDS = %w[technical_observation execution_interruption].freeze
    EVENT_KEYS = %w[schema_version sequence previous_hash occurred_at input provenance record_hash].freeze

    def initialize(directory:)
      @directory = directory
      Host.private_directory!(@directory)
      @path = File.join(@directory, LEDGER_NAME)
    end

    def append(input, observed_cursor:)
      fail!("technical input cursor must be a nonnegative integer") unless observed_cursor.is_a?(Integer) && observed_cursor >= 0
      normalized = validate_input(input)
      replay = replay_ledger
      fail!("technical input cursor is ahead of storage") if observed_cursor > replay.fetch(:cursor)
      existing = replay.fetch(:by_id)[normalized.fetch("input_id")]
      if existing
        fail!("input_id #{normalized['input_id'].inspect} was already used for different technical input") unless canonical(existing.fetch("input")) == canonical(normalized)
        return receipt(existing, replay, true)
      end
      fail!("technical input storage is full; start an explicit successor run") if replay.fetch(:cursor) >= MAX_RECORDS

      event = {
        "schema_version" => SCHEMA_VERSION,
        "sequence" => replay.fetch(:cursor) + 1,
        "previous_hash" => replay.fetch(:record_hash),
        "occurred_at" => Time.now.utc.iso8601(6),
        "input" => normalized,
        "provenance" => {
          "source_kind" => "trusted_adapter_assertion",
          "authenticated_human" => false,
          "authority" => "non_authorizing_technical_evidence"
        }
      }
      event["record_hash"] = record_hash(event)
      line = JSON.generate(event) << "\n"
      fail!("technical input record exceeds #{MAX_LINE_BYTES} bytes") if line.bytesize > MAX_LINE_BYTES
      fail!("technical input storage exceeds #{MAX_LEDGER_BYTES} bytes; start an explicit successor run") if replay.fetch(:bytes) + line.bytesize > MAX_LEDGER_BYTES
      unread = replay.fetch(:events).select { |entry| entry.fetch("sequence") > observed_cursor } + [event]
      if JSON.generate(unread).bytesize > MAX_UNREAD_BYTES
        fail!("unread technical input exceeds #{MAX_UNREAD_BYTES} bytes; run the driver before publishing more input")
      end

      append_line!(line)
      receipt(event, { cursor: event.fetch("sequence"), record_hash: event.fetch("record_hash") }, false)
    end

    def read_after(cursor)
      fail!("technical input cursor must be a nonnegative integer") unless cursor.is_a?(Integer) && cursor >= 0
      replay = replay_ledger
      fail!("technical input cursor is ahead of storage") if cursor > replay.fetch(:cursor)
      events = replay.fetch(:events).select { |event| event.fetch("sequence") > cursor }
      fail!("unread technical input exceeds #{MAX_UNREAD_BYTES} bytes") if JSON.generate(events).bytesize > MAX_UNREAD_BYTES
      { "cursor" => replay.fetch(:cursor), "record_hash" => replay.fetch(:record_hash), "records" => deep_copy(events) }
    end

    def snapshot
      replay = replay_ledger
      { "cursor" => replay.fetch(:cursor), "record_hash" => replay.fetch(:record_hash) }
    end

    private

    def validate_input(input)
      fail!("technical input must be an object") unless input.is_a?(Hash)
      copy = JSON.parse(JSON.generate(input))
      allowed = %w[input_id kind source summary facts observed_job interruption usage]
      fail!("unknown technical input fields") unless (copy.keys - allowed).empty?
      %w[input_id kind source summary].each { |key| fail!("missing technical input field #{key}") unless copy.key?(key) }
      identifier!(copy["input_id"], "input_id")
      fail!("invalid technical input kind") unless KINDS.include?(copy["kind"])
      text!(copy["summary"], "summary", MAX_SUMMARY_BYTES)

      source = exact_object!(copy["source"], %w[adapter_id reference], "source")
      identifier!(source["adapter_id"], "source.adapter_id")
      text!(source["reference"], "source.reference", MAX_REFERENCE_BYTES)

      facts = copy.fetch("facts", [])
      fail!("facts must be an array of at most #{MAX_FACTS} entries") unless facts.is_a?(Array) && facts.length <= MAX_FACTS
      names = facts.map.with_index do |fact, index|
        item = exact_object!(fact, %w[name value], "facts[#{index}]")
        identifier!(item["name"], "facts[#{index}].name")
        text!(item["value"], "facts[#{index}].value", MAX_FACT_VALUE_BYTES)
        item["name"]
      end
      fail!("fact names must be unique") unless names.uniq.length == names.length
      copy["facts"] = facts

      if copy["observed_job"]
        job = exact_object!(copy["observed_job"], %w[job_id status], "observed_job")
        identifier!(job["job_id"], "observed_job.job_id")
        fail!("invalid observed_job.status") unless JOB_STATUSES.include?(job["status"])
      end

      if copy["kind"] == "execution_interruption"
        fail!("execution_interruption requires observed_job") unless copy["observed_job"]
        interruption = exact_object!(copy["interruption"], %w[failed reason_code], "interruption", optional: %w[detail])
        fail!("execution_interruption must record failed:true") unless interruption["failed"] == true
        identifier!(interruption["reason_code"], "interruption.reason_code")
        text!(interruption["detail"], "interruption.detail", MAX_DETAIL_BYTES) if interruption.key?("detail")
      else
        fail!("technical_observation cannot contain interruption") if copy.key?("interruption")
      end

      if copy["usage"]
        usage = copy["usage"]
        fail!("usage must be an object") unless usage.is_a?(Hash)
        fail!("unknown usage counters") unless (usage.keys - COUNTERS).empty?
        fail!("usage must contain at least one counter") if usage.empty?
        usage.each do |name, value|
          fail!("usage.#{name} must be a nonnegative integer") unless value.is_a?(Integer) && value.between?(0, 1_000_000_000_000)
        end
      end
      copy
    rescue JSON::GeneratorError
      fail!("technical input must contain JSON-compatible values")
    end

    def replay_ledger
      return { events: [], by_id: {}, cursor: 0, record_hash: nil, bytes: 0 } unless File.exist?(@path)
      fail!("unsafe technical input ledger") if File.symlink?(@path)
      stat = File.stat(@path)
      fail!("technical input ledger must be a private regular file") unless stat.file? && (stat.mode & 0o077).zero?
      fail!("technical input storage exceeds #{MAX_LEDGER_BYTES} bytes") if stat.size > MAX_LEDGER_BYTES
      events = []
      by_id = {}
      previous_hash = nil
      File.open(@path, File::RDONLY | (defined?(File::NOFOLLOW) ? File::NOFOLLOW : 0)) do |file|
        loop do
          line = file.gets(MAX_LINE_BYTES + 1)
          break unless line
          fail!("technical input ledger exceeds #{MAX_RECORDS} records") if events.length >= MAX_RECORDS
          fail!("technical input ledger is truncated or oversized at sequence #{events.length + 1}") if line.bytesize > MAX_LINE_BYTES || !line.end_with?("\n")
          event = JSON.parse(line)
          verify_event!(event, events.length + 1, previous_hash)
          input = validate_input(event.fetch("input"))
          id = input.fetch("input_id")
          fail!("technical input ledger contains duplicate input_id #{id.inspect}") if by_id.key?(id)
          events << event
          by_id[id] = event
          previous_hash = event.fetch("record_hash")
        end
      end
      { events: events, by_id: by_id, cursor: events.length, record_hash: previous_hash, bytes: stat.size }
    rescue JSON::ParserError => error
      fail!("technical input ledger contains invalid JSON: #{error.message}")
    end

    def verify_event!(event, sequence, previous_hash)
      fail!("technical input event #{sequence} has an invalid schema") unless event.is_a?(Hash) && event.keys.sort == EVENT_KEYS.sort
      fail!("technical input event #{sequence} uses an unsupported schema") unless event["schema_version"] == SCHEMA_VERSION
      fail!("technical input event sequence mismatch") unless event["sequence"] == sequence
      fail!("technical input event #{sequence} previous_hash mismatch") unless event["previous_hash"] == previous_hash
      fail!("technical input event #{sequence} has invalid provenance") unless event["provenance"] == {
        "source_kind" => "trusted_adapter_assertion", "authenticated_human" => false,
        "authority" => "non_authorizing_technical_evidence"
      }
      Time.iso8601(event.fetch("occurred_at"))
      fail!("technical input event #{sequence} record_hash mismatch") unless event["record_hash"] == record_hash(event)
    rescue KeyError, ArgumentError
      fail!("technical input event #{sequence} has invalid metadata")
    end

    def append_line!(line)
      flags = File::WRONLY | File::APPEND | File::CREAT
      flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
      File.open(@path, flags, 0o600) do |file|
        file.chmod(0o600)
        written = 0
        written += file.write(line.byteslice(written, line.bytesize - written)) while written < line.bytesize
        file.flush
        file.fsync
      end
      File.open(@directory, File::RDONLY) { |directory| directory.fsync }
    rescue Errno::ELOOP
      fail!("unsafe technical input ledger")
    end

    def receipt(event, replay, replayed)
      { "cursor" => replay.fetch(:cursor), "record_hash" => replay.fetch(:record_hash),
        "input_cursor" => event.fetch("sequence"), "input_record_hash" => event.fetch("record_hash"),
        "replayed" => replayed, "provenance" => deep_copy(event.fetch("provenance")) }
    end

    def exact_object!(value, required, label, optional: [])
      fail!("#{label} must be an object") unless value.is_a?(Hash)
      fail!("#{label} has invalid fields") unless value.keys.sort == (required + optional.select { |key| value.key?(key) }).sort
      value
    end

    def identifier!(value, label)
      fail!("invalid #{label}") unless value.is_a?(String) && Host::IDENTIFIER.match?(value)
      value
    end

    def text!(value, label, maximum)
      fail!("#{label} must be nonempty text") unless value.is_a?(String) && !value.empty?
      fail!("#{label} exceeds #{maximum} bytes") if value.bytesize > maximum
      value
    end

    def record_hash(event)
      Digest::SHA256.hexdigest(canonical(event.reject { |key, _| key == "record_hash" }))
    end

    def canonical(value)
      case value
      when Hash then "{" + value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical(value[key])}" }.join(",") + "}"
      when Array then "[" + value.map { |item| canonical(item) }.join(",") + "]"
      else JSON.generate(value)
      end
    end

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    end

    def fail!(message)
      raise HrmKernel::Error, message
    end
  end
end
