# frozen_string_literal: true

require "digest"
require "json"
require "pathname"

require_relative "error"

module HrmKernel
  module Evidence
    MAX_EVIDENCE_BYTES = 256 * 1024 * 1024
    MAX_CHECK_REPORT_BYTES = 1024 * 1024
    READ_CHUNK_BYTES = 64 * 1024

    module_function

    def verify!(state, command)
      type = command["type"]
      case type
      when "milestone.create"
        verify_project_root!(command.dig("data", "project_root"))
      when "work_order.submit"
        verify_submission!(state, command.fetch("data"))
      when "milestone.review_ready"
        verify_completed_work!(state)
      when "milestone.review"
        verify_completed_work!(state) if command.dig("data", "decision") == "accepted"
      end

      true
    end

    def verify_project_root!(path)
      fail!("project_root must be an absolute canonical directory") unless path.is_a?(String) && Pathname.new(path).absolute?
      fail!("project_root does not exist or is not a directory") unless File.directory?(path)

      canonical = File.realpath(path)
      fail!("project_root must be an absolute canonical directory") unless path == canonical

      true
    rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR => e
      fail!("project_root cannot be accessed: #{e.message}")
    end

    def verify_submission!(state, data)
      milestone = milestone!(state)
      work_order_id = data["work_order_id"]
      work_order = state.fetch("work_orders", {})[work_order_id]
      fail!("unknown work order #{work_order_id.inspect}") unless work_order.is_a?(Hash)

      declared_paths = Array(work_order["paths"])
      artifacts = evidence_entries!(data["artifacts"], "artifacts")
      checks = evidence_entries!(data["checks"], "checks")
      paths = artifacts.map { |artifact| artifact["path"] }
      fail!("artifact paths must be unique") unless paths.uniq.length == paths.length

      artifacts.each do |artifact|
        path = artifact["path"]
        fail!("artifact path #{path.inspect} is not declared by the work order") unless declared_paths.include?(path)
        verify_file!(milestone.fetch("project_root"), path, artifact["sha256"])
      end

      checks.each do |check|
        path = check["artifact_path"]
        fail!("check report paths must be separate from deliverable artifacts") if paths.include?(path)
        verify_check_report!(
          milestone.fetch("project_root"),
          work_order,
          data["revision"],
          artifacts,
          check
        )
      end

      true
    end

    def evidence_entries!(value, name)
      fail!("#{name} must be an array") unless value.is_a?(Array)
      fail!("#{name} entries must be JSON objects") unless value.all? { |entry| entry.is_a?(Hash) }

      value
    end

    def verify_completed_work!(state)
      milestone = milestone!(state)
      root = milestone.fetch("project_root")

      state.fetch("work_orders", {}).each_value do |work_order|
        next unless work_order["status"] == "completed"

        Array(work_order["artifacts"]).each do |artifact|
          verify_file!(root, artifact["path"], artifact["sha256"])
        end
        Array(work_order["checks"]).each do |check|
          verify_check_report!(
            root,
            work_order,
            work_order.fetch("revision"),
            Array(work_order["artifacts"]),
            check
          )
        end
      end

      true
    end

    def milestone!(state)
      milestone = state.is_a?(Hash) && state["milestone"]
      fail!("milestone has not been created") unless milestone.is_a?(Hash)
      verify_project_root!(milestone["project_root"])
      milestone
    end

    def verify_file!(root, relative_path, expected_sha256)
      path = safe_evidence_path!(root, relative_path)
      read_verified_file!(path, relative_path, expected_sha256, MAX_EVIDENCE_BYTES, false)
      true
    end

    def verify_check_report!(root, work_order, revision, artifacts, check)
      relative_path = check["artifact_path"]
      path = safe_evidence_path!(root, relative_path)
      contents = read_verified_file!(
        path,
        relative_path,
        check["sha256"],
        MAX_CHECK_REPORT_BYTES,
        true
      )
      report = JSON.parse(contents)
      fail!("check report #{relative_path.inspect} must be a JSON object") unless report.is_a?(Hash)

      expected = {
        "check_id" => check["id"],
        "conclusion" => check["conclusion"],
        "work_order_id" => work_order["id"],
        "revision" => revision,
        "artifacts" => artifacts
      }
      expected.each do |key, value|
        unless report[key] == value
          fail!("check report #{relative_path.inspect} has mismatched #{key}")
        end
      end

      true
    rescue JSON::ParserError => e
      fail!("check report #{relative_path.inspect} contains invalid JSON: #{e.message}")
    end

    def read_verified_file!(path, relative_path, expected_sha256, maximum_bytes, capture)
      flags = File::RDONLY
      flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)

      digest = Digest::SHA256.new
      bytes = 0
      contents = capture ? +"" : nil
      File.open(path, flags) do |file|
        before = file.stat
        fail!("evidence path #{relative_path.inspect} is not a regular file") unless before.file?
        fail!("evidence file #{relative_path.inspect} exceeds #{maximum_bytes} bytes") if before.size > maximum_bytes

        while (chunk = file.read(READ_CHUNK_BYTES))
          bytes += chunk.bytesize
          fail!("evidence file #{relative_path.inspect} exceeds #{maximum_bytes} bytes") if bytes > maximum_bytes
          digest.update(chunk)
          contents << chunk if contents
        end

        after = file.stat
        unless before.dev == after.dev && before.ino == after.ino && before.size == after.size &&
               before.mtime == after.mtime
          fail!("evidence file #{relative_path.inspect} changed while it was read")
        end
      end

      fail!("evidence digest mismatch for #{relative_path.inspect}") unless secure_equal?(digest.hexdigest, expected_sha256)
      contents
    rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP, Errno::ENOTDIR => e
      fail!("evidence file #{relative_path.inspect} cannot be read: #{e.message}")
    end

    def safe_evidence_path!(root, relative_path)
      unless relative_path.is_a?(String) && !relative_path.empty? && relative_path.valid_encoding? &&
             !relative_path.include?("\0")
        fail!("invalid evidence path #{relative_path.inspect}")
      end

      pathname = Pathname.new(relative_path)
      clean = pathname.cleanpath.to_s
      if pathname.absolute? || clean == "." || clean == ".." || clean.start_with?("../") || clean != relative_path
        fail!("evidence path escapes project_root: #{relative_path.inspect}")
      end

      candidate = File.join(root, relative_path)
      current = root
      relative_path.split(File::SEPARATOR).each do |part|
        current = File.join(current, part)
        stat = File.lstat(current)
        fail!("symlink evidence paths are not allowed: #{relative_path.inspect}") if stat.symlink?
      end

      root_prefix = root.end_with?(File::SEPARATOR) ? root : "#{root}#{File::SEPARATOR}"
      expanded = File.expand_path(candidate)
      fail!("evidence path escapes project_root: #{relative_path.inspect}") unless expanded.start_with?(root_prefix)
      expanded
    end

    def secure_equal?(actual, expected)
      return false unless expected.is_a?(String) && expected.match?(/\A[0-9a-f]{64}\z/)
      return false unless actual.bytesize == expected.bytesize

      difference = 0
      actual.bytes.zip(expected.bytes) { |a, b| difference |= a ^ b }
      difference.zero?
    end

    def fail!(message)
      raise HrmKernel::Error.new("invalid_evidence", message)
    end
  end
end
