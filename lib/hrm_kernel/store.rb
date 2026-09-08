# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "time"

require_relative "state"
require_relative "evidence"

module HrmKernel
  class Store
    SCHEMA_VERSION = "ap-hrm-interaction/2"
    LEDGER_NAME = "events.jsonl"
    LOCK_NAME = ".lock"
    MAX_LEDGER_LINE_BYTES = 4 * 1024 * 1024
    EVENT_KEYS = %w[schema_version sequence previous_hash occurred_at command event_hash].freeze

    attr_reader :directory

    def initialize(directory)
      unless directory.is_a?(String) && !directory.empty? && Pathname.new(directory).absolute?
        raise HrmKernel::Error, "state directory must be an absolute path"
      end

      @directory = canonical_destination(directory)
      @ledger_path = File.join(@directory, LEDGER_NAME)
      @lock_path = File.join(@directory, LOCK_NAME)
      prepare_directory!
    end

    def transact(command)
      command = validated_command_copy(command)

      with_exclusive_lock do
        replay = replay_ledger
        existing = replay.fetch(:commands_by_id)[command.fetch("command_id")]
        if existing
          unless canonical_json(existing.fetch("command")) == canonical_json(command)
            raise HrmKernel::Error, "command_id #{command['command_id'].inspect} was already used for a different command"
          end

          return receipt(
            replay,
            replay.fetch(:state),
            true,
            existing.fetch("event_hash"),
            existing.fetch("cursor")
          )
        end

        # The empty directory has no projected state. The initial envelope is
        # materialized only when the first command is actually validated.
        base_state = replay.fetch(:state) || State.initial
        next_state = State.apply(base_state, command)
        Evidence.verify!(replay.fetch(:state), command, state_dir: directory)
        sequence = replay.fetch(:cursor) + 1
        event = {
          "schema_version" => SCHEMA_VERSION,
          "sequence" => sequence,
          "previous_hash" => replay.fetch(:event_hash),
          "occurred_at" => Time.now.utc.iso8601(6),
          "command" => command
        }
        event["event_hash"] = event_hash(event)
        append_event!(event)

        receipt(
          { cursor: sequence, event_hash: event.fetch("event_hash") },
          next_state,
          false,
          event.fetch("event_hash"),
          sequence
        )
      end
    end

    def read
      with_exclusive_lock do
        replay = replay_ledger
        {
          "cursor" => replay.fetch(:cursor),
          "event_hash" => replay.fetch(:event_hash),
          "state" => deep_copy(replay.fetch(:state))
        }
      end
    end

    def project(role: "orchestrator", actor_id: nil)
      with_exclusive_lock do
        replay = replay_ledger
        {
          "cursor" => replay.fetch(:cursor),
          "event_hash" => replay.fetch(:event_hash),
          "projection" => project_state(replay.fetch(:state), role, actor_id)
        }
      end
    end

    def verify!
      with_exclusive_lock do
        replay = replay_ledger
        {
          "cursor" => replay.fetch(:cursor),
          "event_hash" => replay.fetch(:event_hash),
          "valid" => true
        }
      end
    end

    private

    def receipt(replay, state, replayed, command_event_hash, command_cursor)
      {
        "cursor" => replay.fetch(:cursor),
        "event_hash" => replay.fetch(:event_hash),
        "command_cursor" => command_cursor,
        "command_event_hash" => command_event_hash,
        "replayed" => replayed,
        "projection" => project_state(state, "orchestrator", nil)
      }
    end

    def project_state(state, role, actor_id)
      return nil if state.nil?

      State.project(state, role: role, actor_id: actor_id)
    end

    def replay_ledger
      return empty_replay unless File.exist?(@ledger_path)

      ensure_safe_path!(@ledger_path, regular: true)
      state = nil
      cursor = 0
      previous_hash = nil
      commands_by_id = {}

      flags = File::RDONLY
      flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
      File.open(@ledger_path, flags) do |ledger|
        loop do
          line = ledger.gets(MAX_LEDGER_LINE_BYTES + 1)
          break if line.nil?
          if line.bytesize > MAX_LEDGER_LINE_BYTES || !line.end_with?("\n")
            raise HrmKernel::Error, "ledger is truncated or contains an oversized event at sequence #{cursor + 1}"
          end
          raise HrmKernel::Error, "ledger contains a blank event at sequence #{cursor + 1}" if line.strip.empty?

          event = parse_event(line, cursor + 1)
          verify_event!(event, cursor + 1, previous_hash)
          command = event.fetch("command")
          command = validated_command_copy(command)
          command_id = command.fetch("command_id")
          if commands_by_id.key?(command_id)
            raise HrmKernel::Error, "ledger contains duplicate command_id #{command_id.inspect}"
          end

          state = State.apply(state || State.initial, command)
          cursor += 1
          previous_hash = event.fetch("event_hash")
          commands_by_id[command_id] = {
            "command" => command,
            "event_hash" => event.fetch("event_hash"),
            "cursor" => cursor
          }
        end
      end

      { state: state, cursor: cursor, event_hash: previous_hash, commands_by_id: commands_by_id }
    rescue JSON::ParserError => e
      raise HrmKernel::Error, "ledger contains invalid JSON: #{e.message}"
    end

    def empty_replay
      { state: nil, cursor: 0, event_hash: nil, commands_by_id: {} }
    end

    def parse_event(line, sequence)
      event = JSON.parse(line)
      raise HrmKernel::Error, "ledger event #{sequence} must be a JSON object" unless event.is_a?(Hash)
      event
    rescue JSON::ParserError => e
      raise HrmKernel::Error, "ledger event #{sequence} contains invalid JSON: #{e.message}"
    end

    def verify_event!(event, expected_sequence, expected_previous_hash)
      unless event.keys.sort == EVENT_KEYS.sort
        raise HrmKernel::Error, "ledger event #{expected_sequence} has an invalid schema"
      end
      unless event["schema_version"] == SCHEMA_VERSION
        raise HrmKernel::Error, "ledger event #{expected_sequence} uses unsupported schema #{event['schema_version'].inspect}"
      end
      unless event["sequence"] == expected_sequence
        raise HrmKernel::Error, "ledger event sequence mismatch: expected #{expected_sequence}, got #{event['sequence'].inspect}"
      end
      unless event["previous_hash"] == expected_previous_hash
        raise HrmKernel::Error, "ledger event #{expected_sequence} previous_hash mismatch"
      end
      unless event["occurred_at"].is_a?(String) && event["occurred_at"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/)
        raise HrmKernel::Error, "ledger event #{expected_sequence} has an invalid timestamp"
      end
      begin
        Time.iso8601(event.fetch("occurred_at"))
      rescue ArgumentError
        raise HrmKernel::Error, "ledger event #{expected_sequence} has an invalid timestamp"
      end
      unless event["event_hash"].is_a?(String) && event["event_hash"].match?(/\A[0-9a-f]{64}\z/)
        raise HrmKernel::Error, "ledger event #{expected_sequence} has an invalid event_hash"
      end
      unless event["event_hash"] == event_hash(event)
        raise HrmKernel::Error, "ledger event #{expected_sequence} event_hash mismatch"
      end
    end

    def append_event!(event)
      existed = File.exist?(@ledger_path)
      ensure_safe_path!(@ledger_path, regular: true) if existed
      line = JSON.generate(event) << "\n"
      raise HrmKernel::Error, "event exceeds maximum ledger line size" if line.bytesize > MAX_LEDGER_LINE_BYTES

      open_private_file(@ledger_path, File::WRONLY | File::APPEND) do |ledger, created|
        stat = ledger.stat
        raise HrmKernel::Error, "ledger is not a regular file" unless stat.file?
        validate_private_file_mode!(stat, @ledger_path)
        written = 0
        written += ledger.write(line.byteslice(written, line.bytesize - written)) while written < line.bytesize
        ledger.flush
        ledger.fsync
        existed = !created
      end
      fsync_directory! unless existed
    end

    def with_exclusive_lock
      ensure_safe_directory!
      open_private_file(@lock_path, File::RDWR) do |lock, _created|
        raise HrmKernel::Error, "state lock is not a regular file" unless lock.stat.file?
        validate_private_file_mode!(lock.stat, @lock_path)
        raise HrmKernel::Error, "cannot lock state directory" unless lock.flock(File::LOCK_EX)
        ensure_safe_directory!
        yield
      end
    rescue Errno::ELOOP => e
      raise HrmKernel::Error, "unsafe symlink in state directory: #{e.message}"
    end

    def prepare_directory!
      ensure_no_symlink_components!(@directory)
      unless File.exist?(@directory)
        FileUtils.mkdir_p(@directory, mode: 0o700)
      end
      ensure_safe_directory!
      mode = File.lstat(@directory).mode & 0o777
      unless mode == 0o700
        raise HrmKernel::Error, "state directory must have mode 0700 (found #{format('%04o', mode)})"
      end
      validate_existing_layout!
    rescue SystemCallError => e
      raise HrmKernel::Error, "cannot prepare state directory: #{e.message}"
    end

    def validate_existing_layout!
      children = Dir.children(@directory)
      runtime_directories = %w[host-jobs execution coordinator]
      unknown = children - [LEDGER_NAME, LOCK_NAME, ".execution-receipt-key", *runtime_directories]
      unless unknown.empty?
        raise HrmKernel::Error, "state directory contains unrelated entries: #{unknown.sort.join(', ')}"
      end
      (children & runtime_directories).each do |name|
        path = File.join(@directory, name)
        ensure_no_symlink_components!(path)
        stat = File.lstat(path)
        unless stat.directory? && (stat.mode & 0o777) == 0o700
          raise HrmKernel::Error, "runtime state directory must be a private directory: #{name}"
        end
      end
      key_path = File.join(@directory, ".execution-receipt-key")
      ensure_safe_path!(key_path, regular: true) if children.include?(".execution-receipt-key")
      return if children.empty?
      unless children.include?(LOCK_NAME)
        raise HrmKernel::Error, "existing state directory is missing #{LOCK_NAME}"
      end

      ensure_safe_path!(@lock_path, regular: true)
      flags = File::RDWR
      flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
      File.open(@lock_path, flags) do |lock|
        raise HrmKernel::Error, "cannot lock state directory" unless lock.flock(File::LOCK_EX)
        replay_ledger
      end
    end

    def ensure_safe_directory!
      ensure_no_symlink_components!(@directory)
      stat = File.lstat(@directory)
      raise HrmKernel::Error, "state directory is not a directory" unless stat.directory? && !stat.symlink?
    end

    def ensure_no_symlink_components!(path)
      current = File::SEPARATOR
      Pathname.new(path).each_filename do |part|
        current = File.join(current, part)
        next unless File.exist?(current) || File.symlink?(current)

        raise HrmKernel::Error, "symlink path component is not allowed: #{current}" if File.lstat(current).symlink?
      end
    end

    def ensure_safe_path!(path, regular: false)
      ensure_no_symlink_components!(path)
      stat = File.lstat(path)
      raise HrmKernel::Error, "unsafe symlink path: #{path}" if stat.symlink?
      raise HrmKernel::Error, "expected a regular file: #{path}" if regular && !stat.file?
      validate_private_file_mode!(stat, path) if regular
      true
    rescue Errno::ENOENT
      raise HrmKernel::Error, "missing state file: #{path}"
    end

    def open_private_file(path, access_flags)
      nofollow = defined?(File::NOFOLLOW) ? File::NOFOLLOW : 0
      created = false
      file = begin
        created = true
        File.open(path, access_flags | File::CREAT | File::EXCL | nofollow, 0o600)
      rescue Errno::EEXIST
        created = false
        ensure_safe_path!(path, regular: true)
        File.open(path, access_flags | nofollow)
      end
      file.chmod(0o600) if created
      yield file, created
    ensure
      file.close if file && !file.closed?
    end

    def validate_private_file_mode!(stat, path)
      mode = stat.mode & 0o777
      return if mode == 0o600

      raise HrmKernel::Error, "state file must have mode 0600: #{path} (found #{format('%04o', mode)})"
    end

    def canonical_destination(path)
      expanded = File.expand_path(path)
      raise HrmKernel::Error, "state directory itself may not be a symlink" if File.symlink?(expanded)

      ancestor = expanded
      missing = []
      until File.exist?(ancestor)
        parent = File.dirname(ancestor)
        raise HrmKernel::Error, "cannot resolve state directory parent" if parent == ancestor
        missing.unshift(File.basename(ancestor))
        ancestor = parent
      end
      File.join(File.realpath(ancestor), *missing)
    rescue SystemCallError => e
      raise HrmKernel::Error, "cannot resolve state directory: #{e.message}"
    end

    def fsync_directory!
      File.open(@directory, File::RDONLY) { |directory_io| directory_io.fsync }
    rescue Errno::EINVAL, Errno::EISDIR
      nil
    end

    def validated_command_copy(command)
      unless command.is_a?(Hash)
        raise HrmKernel::Error, "command must be a JSON object"
      end

      validate_json_shape!(command, "command")
      copy = deep_copy(command)
      required = %w[command_id type actor data]
      unless copy.keys.sort == required.sort
        raise HrmKernel::Error, "command must contain exactly command_id, type, actor, and data"
      end
      unless copy["command_id"].is_a?(String) && !copy["command_id"].empty?
        raise HrmKernel::Error, "command_id must be a non-empty string"
      end
      unless copy["type"].is_a?(String) && !copy["type"].empty?
        raise HrmKernel::Error, "type must be a non-empty string"
      end
      actor = copy["actor"]
      unless actor.is_a?(Hash) && actor.keys.sort == %w[id role] &&
             actor["id"].is_a?(String) && !actor["id"].empty? &&
             actor["role"].is_a?(String) && !actor["role"].empty?
        raise HrmKernel::Error, "actor must contain non-empty id and role strings"
      end
      raise HrmKernel::Error, "data must be a JSON object" unless copy["data"].is_a?(Hash)

      copy
    rescue JSON::GeneratorError => e
      raise HrmKernel::Error, "command is not valid JSON data: #{e.message}"
    end

    def validate_json_shape!(value, path)
      case value
      when Hash
        value.each do |key, child|
          raise HrmKernel::Error, "#{path} object keys must be strings" unless key.is_a?(String)
          validate_json_shape!(child, "#{path}.#{key}")
        end
      when Array
        value.each_with_index { |child, index| validate_json_shape!(child, "#{path}[#{index}]") }
      when String, Integer, TrueClass, FalseClass, NilClass
        nil
      when Float
        raise HrmKernel::Error, "#{path} contains a non-finite number" unless value.finite?
      else
        raise HrmKernel::Error, "#{path} contains unsupported JSON value #{value.class}"
      end
    end

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    end

    def canonical_json(value)
      JSON.generate(canonicalize(value))
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.sort.each_with_object({}) { |key, sorted| sorted[key] = canonicalize(value.fetch(key)) }
      when Array
        value.map { |child| canonicalize(child) }
      else
        value
      end
    end

    def event_hash(event)
      without_hash = event.reject { |key, _value| key == "event_hash" }
      Digest::SHA256.hexdigest(canonical_json(without_hash))
    end
  end
end
