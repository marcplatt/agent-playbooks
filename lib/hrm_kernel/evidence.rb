# frozen_string_literal: true

require "digest"
require "json"
require "pathname"

require_relative "error"
require_relative "execution"

module HrmKernel
  module Evidence
    MAX_EVIDENCE_BYTES = 256 * 1024 * 1024
    MAX_CHECK_REPORT_BYTES = 1024 * 1024
    READ_CHUNK_BYTES = 64 * 1024

    module_function

    def verify!(state, command, state_dir: nil)
      type = command["type"]
      case type
      when "milestone.create"
        verify_project_root!(command.dig("data", "project_root"))
      when "work_order.submit", "work_order.refresh_evidence"
        verify_submission!(state, command.fetch("data"), state_dir: state_dir)
      when "milestone.review_ready"
        verify_completed_work!(state, state_dir: state_dir)
      when "milestone.assess", "finding.resolve"
        verify_completed_work!(state, state_dir: state_dir)
      when "milestone.review"
        verify_completed_work!(state, state_dir: state_dir) if command.dig("data", "decision") == "accepted"
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

    def verify_submission!(state, data, state_dir: nil)
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
        if native_execution?(milestone) && !File.exist?(File.join(milestone.fetch("project_root"), path))
          verify_deleted_file!(milestone.fetch("project_root"), path, artifact["sha256"])
        else
          verify_file!(milestone.fetch("project_root"), path, artifact["sha256"])
        end
      end

      checks.each do |check|
        path = check["artifact_path"]
        fail!("check report paths must be separate from deliverable artifacts") if paths.include?(path)
        if native_execution?(milestone)
          verify_native_check_report!(
            milestone, work_order, data["claim_id"], data["revision"], artifacts,
            check, state_dir: state_dir, historical_continuation: false
          )
        else
          verify_check_report!(
            milestone.fetch("project_root"),
            work_order,
            data["revision"],
            artifacts,
            check
          )
        end
      end

      true
    end

    def evidence_entries!(value, name)
      fail!("#{name} must be an array") unless value.is_a?(Array)
      fail!("#{name} entries must be JSON objects") unless value.all? { |entry| entry.is_a?(Hash) }

      value
    end

    def verify_completed_work!(state, state_dir: nil, verification: :current)
      unless %i[current historical_continuation].include?(verification)
        fail!("unsupported completed-work verification mode")
      end
      milestone = milestone!(state)
      root = milestone.fetch("project_root")

      state.fetch("work_orders", {}).each_value do |work_order|
        next unless work_order["status"] == "completed"
        verify_completed_order!(milestone, work_order, state_dir: state_dir,
          historical_continuation: verification == :historical_continuation)
      end

      true
    end

    def validation_projection(state, state_dir:)
      active = active_environment_id(state_dir)
      return nil unless active
      milestone = milestone!(state)
      completed = state.fetch("work_orders", {}).values.select { |order| order["status"] == "completed" }
      pending = completed.reject do |order|
        begin
          verify_completed_order!(milestone, order, state_dir: state_dir, historical_continuation: false)
          true
        rescue HrmKernel::Error
          false
        end
      end
      {
        "active_environment_id" => active,
        "old_checks_eligible" => false,
        "pending_work_order_ids" => pending.map { |order| order.fetch("id") }.sort,
        "review_eligible" => pending.empty?
      }
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

    def verify_native_check_report!(milestone, work_order, claim_id, revision, artifacts, check,
                                    state_dir:, historical_continuation:)
      fail!("native check verification requires state_dir") unless state_dir.is_a?(String)
      relative_path = check["artifact_path"]
      path = safe_evidence_path!(milestone.fetch("project_root"), relative_path)
      contents = read_verified_file!(path, relative_path, check["sha256"], MAX_CHECK_REPORT_BYTES, true)
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
        fail!("check report #{relative_path.inspect} has mismatched #{key}") unless report[key] == value
      end
      descriptor = report["execution"]
      fail!("check report #{relative_path.inspect} lacks native execution evidence") unless descriptor.is_a?(Hash)
      runner = HrmKernel::Execution.new(
        project_root: milestone.fetch("project_root"),
        state_dir: state_dir,
        repository_view: active_environment_config(state_dir)&.fetch("check_repository", nil)
      )
      expected_binding = {
        "work_order_id" => work_order.fetch("id"),
        "claim_id" => claim_id,
        "revision" => revision,
        "requirement_revisions" => work_order.fetch("requirement_revisions"),
        "work_order_contract_digest" => HrmKernel::Execution.contract_digest(milestone, work_order)
      }
      receipt = runner.verify_receipt!(
        descriptor,
        expected_binding: expected_binding,
        current_exact: !historical_continuation,
        historical_authentication_only: historical_continuation
      )
      fail!("native receipt check id mismatch") unless receipt["check_id"] == check["id"]
      fail!("native receipt conclusion mismatch") unless receipt["conclusion"] == check["conclusion"]
      active_environment = active_environment_id(state_dir)
      if !historical_continuation && active_environment && receipt["environment_id"] != active_environment
        fail!("native receipt belongs to historical environment #{receipt['environment_id'].inspect}; active environment is #{active_environment.inspect}")
      end
      verify_native_artifacts!(receipt.fetch("candidate"), work_order, artifacts)
      true
    rescue JSON::ParserError => e
      fail!("check report #{relative_path.inspect} contains invalid JSON: #{e.message}")
    end

    def verify_native_artifacts!(candidate, work_order, artifacts)
      declared = Array(work_order["paths"])
      relevant = Array(candidate["changes"]).select do |entry|
        declared.any? { |path| native_path_matches?(entry["path"], path) }
      end
      expected = relevant.map do |entry|
        sha256 = if entry["status"] == "D"
                   Digest::SHA256.hexdigest("deleted\0#{entry.fetch('path')}")
                 else
                   entry.fetch("sha256")
                 end
        { "path" => entry.fetch("path"), "sha256" => sha256 }
      end.sort_by { |entry| entry["path"] }
      actual = artifacts.sort_by { |entry| entry["path"] }
      fail!("submitted artifacts do not match the native candidate") unless actual == expected
      true
    end

    def native_path_matches?(path, declaration)
      if declaration.include?("*") || declaration.include?("?") || declaration.include?("[")
        File.fnmatch?(declaration, path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
      else
        path == declaration
      end
    end

    def verify_deleted_file!(root, relative_path, expected_sha256)
      pathname = Pathname.new(relative_path)
      clean = pathname.cleanpath.to_s
      if pathname.absolute? || clean == "." || clean == ".." || clean.start_with?("../") || clean != relative_path
        fail!("evidence path escapes project_root: #{relative_path.inspect}")
      end
      current = root
      parts = relative_path.split(File::SEPARATOR)
      parts[0...-1].each do |part|
        current = File.join(current, part)
        stat = File.lstat(current)
        fail!("symlink evidence paths are not allowed: #{relative_path.inspect}") if stat.symlink?
      end
      target = File.join(root, relative_path)
      fail!("deleted artifact #{relative_path.inspect} exists") if File.exist?(target) || File.symlink?(target)
      expected = Digest::SHA256.hexdigest("deleted\0#{relative_path}")
      fail!("deleted artifact digest mismatch for #{relative_path.inspect}") unless secure_equal?(expected, expected_sha256)
      true
    rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP, Errno::ENOTDIR => e
      fail!("deleted artifact path #{relative_path.inspect} cannot be verified: #{e.message}")
    end

    def native_execution?(milestone)
      milestone["mode"] == "implementation"
    end

    def verify_completed_order!(milestone, work_order, state_dir:, historical_continuation:)
      root = milestone.fetch("project_root")
      Array(work_order["artifacts"]).each do |artifact|
        if native_execution?(milestone) && !File.exist?(File.join(root, artifact["path"]))
          verify_deleted_file!(root, artifact["path"], artifact["sha256"])
        else
          verify_file!(root, artifact["path"], artifact["sha256"])
        end
      end
      Array(work_order["checks"]).each do |check|
        if native_execution?(milestone)
          verify_native_check_report!(
            milestone, work_order, Array(work_order["claim_history"]).last,
            work_order.fetch("revision"), Array(work_order["artifacts"]), check,
            state_dir: state_dir, historical_continuation: historical_continuation
          )
        else
          verify_check_report!(root, work_order, work_order.fetch("revision"), Array(work_order["artifacts"]), check)
        end
      end
      true
    end

    def active_environment_id(state_dir)
      active_environment_config(state_dir)&.fetch("environment_id")
    end

    def active_environment_config(state_dir)
      return nil unless state_dir.is_a?(String)
      path = File.join(state_dir, "driver", "config.json")
      return nil unless File.exist?(path)
      flags = File::RDONLY
      flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
      bytes = File.open(path, flags) do |file|
        stat = file.stat
        fail!("Driver configuration is not a private regular file") unless stat.file? && stat.uid == Process.uid && (stat.mode & 0o077).zero?
        fail!("Driver configuration exceeds evidence bound") if stat.size > MAX_CHECK_REPORT_BYTES
        file.read(MAX_CHECK_REPORT_BYTES + 1)
      end
      config = JSON.parse(bytes)
      transition = config.dig("continuation", "environment_transition")
      return nil unless transition
      fail!("environment transition configuration is malformed") unless transition.is_a?(Hash) &&
        transition["active_environment_id"].is_a?(String) && transition["old_checks_eligible_for_new_claims"].equal?(false)
      fail!("active validation environment differs from Driver configuration") unless transition["active_environment_id"] == config["environment_id"]
      config
    rescue JSON::ParserError => error
      fail!("Driver configuration contains invalid JSON: #{error.message}")
    rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => error
      fail!("Driver configuration cannot be read: #{error.message}")
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
