# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "securerandom"
require "time"
require "tmpdir"

require_relative "error"
require_relative "execution"
require_relative "host"
require_relative "store"
require_relative "supervisor_input"

module HrmKernel
  # Copies a stopped, verified run into a new private state root. The ledger and
  # historical receipts are evidence: they are copied byte-for-byte and never
  # rewritten. Only the destination Driver configuration/runtime are derived so
  # the new kernel must make a fresh projection and a fresh orchestration request.
  class RunContinuation
    LEGACY_SCHEMA_VERSION = "ap-hrm-run-continuation/1"
    SCHEMA_VERSION = "ap-hrm-run-continuation/2"
    PROVENANCE_SCHEMA = "ap-hrm-supervisor-continuation/1"
    TRANSITIONS = {
      "AP-INTERACT RC.35" => { "target" => "AP-INTERACT RC.36", "environment_replacement" => false },
      "AP-INTERACT RC.36" => { "target" => "AP-INTERACT RC.37", "environment_replacement" => true }
    }.freeze
    ENVIRONMENT_FIELDS = %w[environment_id read_roots environment_allowlist preflight_checks].freeze
    MAX_FILE_BYTES = 16 * 1024 * 1024
    MAX_TOTAL_BYTES = 256 * 1024 * 1024
    MAX_ENTRIES = 20_000
    GIT_REVISION = /\A[0-9a-f]{40}\z/.freeze
    CONTINUATION_DIRECTORY = File.join("driver", "continuation")
    MANIFEST_PATH = File.join(CONTINUATION_DIRECTORY, "manifest.json")
    RC37_CONTINUATION_DIRECTORY = File.join(CONTINUATION_DIRECTORY, "rc37")
    RC37_MANIFEST_PATH = File.join(RC37_CONTINUATION_DIRECTORY, "manifest.json")

    class << self
      def clone(source_state_dir:, destination_state_dir:, new_run_id:, source_kernel_root:,
                source_kernel_revision:, controller_stopped:, supervisor_provenance:,
                environment_replacement: nil, production: true)
        new(
          source_state_dir: source_state_dir,
          destination_state_dir: destination_state_dir,
          new_run_id: new_run_id,
          source_kernel_root: source_kernel_root,
          source_kernel_revision: source_kernel_revision,
          controller_stopped: controller_stopped,
          supervisor_provenance: supervisor_provenance,
          environment_replacement: environment_replacement,
          production: production
        ).clone!
      end
    end

    def initialize(source_state_dir:, destination_state_dir:, new_run_id:, source_kernel_root:,
                   source_kernel_revision:, controller_stopped:, supervisor_provenance:,
                   environment_replacement: nil, production: true)
      @source = canonical_existing_directory(source_state_dir, "source state directory")
      @destination = canonical_destination(destination_state_dir)
      @new_run_id = new_run_id
      @source_kernel_root = canonical_existing_directory(source_kernel_root, "source kernel root")
      @declared_source_revision = source_kernel_revision
      @controller_stopped = controller_stopped
      @supervisor_provenance = validate_provenance(supervisor_provenance)
      @environment_replacement_input = environment_replacement
      @production = production
      validate_request!
    end

    def clone!
      with_source_driver_lock do
        source = verify_source!
        request = request_record(source)
        return verify_idempotent_destination!(request) if File.exist?(@destination)

        staging = "#{@destination}.continuation-#{Process.pid}-#{SecureRandom.hex(6)}"
        destination_created = false
        fail!("continuation staging path already exists") if File.exist?(staging) || File.symlink?(staging)
        begin
          copy_tree(@source, staging)
          derive_destination!(staging, source, request)
          verify_source_unchanged!(source.fetch("tree"))
          File.rename(staging, @destination)
          destination_created = true
          prepare_target_preflight!(@destination, source)
          finalize_destination!(@destination, source, request)
          fsync_directory(File.dirname(@destination))
          manifest = verify_created_destination!(request)
          destination_created = false
          manifest
        ensure
          FileUtils.remove_entry(staging) if staging && File.directory?(staging)
          FileUtils.remove_entry(@destination) if destination_created && File.directory?(@destination)
        end
      end
    rescue Errno::ELOOP => error
      fail!("unsafe symlink while continuing run: #{error.message}")
    rescue SystemCallError => error
      fail!("cannot create continued run: #{error.message}")
    end

    private

    def validate_request!
      fail!("new run id is invalid") unless @new_run_id.is_a?(String) &&
        Host::IDENTIFIER.match?(@new_run_id) && @new_run_id.length <= 40
      fail!("source kernel revision must be a full Git commit") unless @declared_source_revision.is_a?(String) &&
        GIT_REVISION.match?(@declared_source_revision)
      fail!("controller_stopped must be explicitly true") unless @controller_stopped.equal?(true)
      fail!("production must be true or false") unless @production.equal?(true) || @production.equal?(false)
      fail!("source and destination state roots overlap") if beneath?(@source, @destination) || beneath?(@destination, @source)
      unless @production
        temporary_root = File.realpath(Dir.tmpdir)
        unless [@source, @destination, @source_kernel_root].all? { |path| beneath?(path, temporary_root) }
          fail!("non-production continuation is restricted to temporary test fixtures")
        end
      end
    end

    def validate_provenance(value)
      fail!("supervisor provenance must be an object") unless value.is_a?(Hash)
      copy = JSON.parse(JSON.generate(value))
      required = %w[asserted_at commission_id schema_version source supervisor_id]
      fail!("supervisor provenance fields are invalid") unless copy.keys.sort == required
      fail!("supervisor provenance schema is unsupported") unless copy["schema_version"] == PROVENANCE_SCHEMA
      %w[supervisor_id source].each do |key|
        fail!("supervisor provenance #{key} must be nonempty text") unless copy[key].is_a?(String) && !copy[key].empty?
      end
      fail!("supervisor commission id is invalid") unless copy["commission_id"].is_a?(String) &&
        Host::IDENTIFIER.match?(copy["commission_id"])
      begin
        Time.iso8601(copy.fetch("asserted_at"))
        unless /(?:Z|[+-]\d{2}:\d{2})\z/.match?(copy["asserted_at"])
          fail!("supervisor provenance asserted_at must include a UTC offset")
        end
      rescue ArgumentError
        fail!("supervisor provenance asserted_at must be ISO8601")
      end
      copy
    rescue JSON::GeneratorError
      fail!("supervisor provenance must contain JSON values")
    end

    def with_source_driver_lock
      driver = File.join(@source, "driver")
      ensure_private_directory(driver, "source driver directory")
      path = File.join(driver, ".lock")
      fail!("source driver lock is a symlink") if File.symlink?(path)
      fail!("source Driver lock is missing") unless File.file?(path)
      flags = File::RDWR
      flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
      File.open(path, flags) do |lock|
        fail!("source driver lock must be a private regular file") unless lock.stat.file? && (lock.stat.mode & 0o077).zero?
        fail!("source Driver is still running or its stop is not observable") unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        yield
      end
    end

    def verify_source!
      source_revision = verify_git_checkout!(@source_kernel_root, expected: @declared_source_revision,
        require_clean: true, scope: "source kernel")
      source_version = source_kernel_version(source_revision)
      transition = TRANSITIONS.fetch(source_version) { fail!("declared source pin is not a supported continuation source") }
      environment_replacement = normalize_environment_replacement(source_version)
      target_root = File.realpath(File.expand_path("../..", __dir__))
      target_revision = verify_git_checkout!(target_root, require_clean: @production, scope: "executing target kernel")
      target_version = transition.fetch("target")
      target_version_verified = verify_target_kernel_version!(target_root, target_revision.fetch("revision"),
        target_version, required: @production)
      if @production && target_revision.fetch("revision") == source_revision
        fail!("production continuation requires a target kernel revision newer than its source pin")
      end

      # Constructors used below are intended to be read-only for a valid RC35
      # run. Capture first so an unexpected mkdir/key/chmod is detected.
      tree = snapshot_tree(@source)
      store = Store.new(@source)
      store_receipt = store.verify!
      state = store.read.fetch("state")
      config_bytes = read_private(File.join(@source, "driver", "config.json"))
      runtime_bytes = read_private(File.join(@source, "driver", "runtime.json"))
      preflight_bytes = read_private(File.join(@source, "driver", "preflight.json"))
      config = parse_object(config_bytes, "source Driver configuration")
      runtime = parse_object(runtime_bytes, "source Driver runtime")
      preflight = parse_array(preflight_bytes, "source Driver preflight")
      validate_source_generation!(source_version, config, runtime)
      fail!("new run id must differ from the source run id") if config["run_id"] == @new_run_id
      fail!("source Driver has a pending dispatch") if runtime.key?("pending_dispatch")
      fail!("source Driver has a pending job registration") if runtime.key?("pending_job_registration")
      fail!("source Driver runtime round is invalid") unless runtime["round"].is_a?(Integer) && runtime["round"] >= 0
      fail!("source Driver job lists are malformed") unless string_array?(runtime["jobs"]) && string_array?(runtime["seen_jobs"])
      fail!("source Driver configuration run id is invalid") unless config["run_id"].is_a?(String) && Host::IDENTIFIER.match?(config["run_id"])
      fail!("source Driver project root differs from the ledger") unless File.realpath(config.fetch("project_root")) == state.dig("milestone", "project_root")
      fail!("source Driver max_turns is invalid") unless config["max_turns"].is_a?(Integer) && config["max_turns"].between?(1, 100)
      fail!("source Driver consumed more than its turn budget") if runtime["round"] > config["max_turns"]
      fail!("source Driver outcome is invalid") unless %w[active review_ready closed operator_input engineering_stalled host_failure preflight_failed turn_limit].include?(runtime["outcome"])
      fail!("source Driver runtime feedback is malformed") unless runtime["feedback"].is_a?(Array)
      fail!("source Driver seen_jobs is not a subset of jobs") unless (runtime["seen_jobs"] - runtime["jobs"]).empty?
      if runtime["orchestrator_technical_input_cursor"]
        fail!("source Driver has an in-flight technical-input cursor")
      end
      verify_preflight_records!(config, preflight)
      verify_driver_requests!
      Evidence.verify_completed_work!(state, state_dir: @source)

      supervisor = SupervisorInput.new(directory: File.join(@source, "driver")).snapshot
      observed_technical_cursor = runtime.fetch("observed_technical_input_cursor", 0)
      unless observed_technical_cursor.is_a?(Integer) && observed_technical_cursor.between?(0, supervisor.fetch("cursor"))
        fail!("source Driver acknowledged technical-input cursor is invalid")
      end

      host = Host.new(state_dir: @source)
      statuses = verify_host_records!(host)
      referenced = (runtime.fetch("jobs") + [runtime["orchestrator_job"], runtime["resume_job"]]).compact
      fail!("source Driver references a missing Host job") unless (referenced - statuses.keys).empty?
      active = statuses.values.select { |status| %w[running launch_unknown].include?(status["status"]) }
      fail!("source has a running or uncertain native job: #{active.map { |item| item['job_id'] }.sort.join(', ')}") unless active.empty?
      next_job_id = "#{@new_run_id}-astra-#{runtime['round'] + 1}"
      fail!("new run id would collide with copied Host history") if statuses.key?(next_job_id)

      if environment_replacement
        environment_replacement = validate_environment_replacement!(environment_replacement, config)
        reject_old_environment_completion!(state)
      end

      verify_source_unchanged!(tree)
      {
        "store" => store_receipt,
        "config" => config, "config_bytes" => config_bytes,
        "runtime" => runtime, "runtime_bytes" => runtime_bytes,
        "preflight_bytes" => preflight_bytes,
        "statuses" => statuses, "tree" => tree,
        "state" => state,
        "source_kernel_version" => source_version,
        "source_kernel_revision" => source_revision,
        "target_kernel_version" => target_version,
        "target_kernel_root" => target_root,
        "target_kernel_revision" => target_revision.fetch("revision"),
        "target_checkout_clean" => target_revision.fetch("clean"),
        "target_version_verified" => target_version_verified,
        "environment_replacement" => environment_replacement,
        "supervisor_input" => supervisor,
        "observed_technical_input_cursor" => observed_technical_cursor
      }
    end

    def validate_source_generation!(source_version, config, runtime)
      journal = File.join(@source, "driver", SupervisorInput::LEDGER_NAME)
      if source_version == "AP-INTERACT RC.35"
        fail!("RC35 source is already a versioned continuation") if config.key?("continuation") || runtime.key?("continuation")
        fail!("RC35 source contains a supervisor-input journal") if File.exist?(journal)
        fail!("RC35 to RC36 continuation does not accept an environment replacement") if @environment_replacement_input
      elsif config["continuation"]
        manifest_path = File.join(@source, MANIFEST_PATH)
        fail!("RC36 continuation provenance is missing") unless File.file?(manifest_path)
        manifest = parse_object(read_private(manifest_path), "source continuation manifest")
        fail!("source continuation target version is not RC36") unless manifest["target_kernel_version"] == source_version
        verify_prior_continuation!(manifest)
      end
    end

    def normalize_environment_replacement(source_version)
      required = TRANSITIONS.fetch(source_version).fetch("environment_replacement")
      if required
        fail!("RC36 to RC37 continuation requires environment_replacement") unless @environment_replacement_input.is_a?(Hash)
        JSON.parse(JSON.generate(@environment_replacement_input))
      else
        nil
      end
    rescue JSON::GeneratorError
      fail!("environment replacement must contain JSON values")
    end

    def validate_environment_replacement!(replacement, source_config)
      fail!("environment replacement fields are invalid") unless replacement.keys.sort == ENVIRONMENT_FIELDS.sort
      fail!("source environment configuration is incomplete") unless ENVIRONMENT_FIELDS.all? { |field| source_config.key?(field) }
      fail!("source environment_id is invalid") unless source_config["environment_id"].is_a?(String) &&
        Host::IDENTIFIER.match?(source_config["environment_id"])
      environment_id = replacement["environment_id"]
      fail!("replacement environment_id is invalid") unless environment_id.is_a?(String) && Host::IDENTIFIER.match?(environment_id)
      fail!("replacement environment_id must differ from the frozen source") if environment_id == source_config["environment_id"]

      roots = replacement["read_roots"]
      fail!("replacement read_roots must be a unique string array") unless roots.is_a?(Array) &&
        roots.uniq == roots && roots.all? { |path| path.is_a?(String) && Pathname.new(path).absolute? }
      replacement["read_roots"] = roots.map do |path|
        fail!("replacement read root itself may not be a symlink") if File.symlink?(path)
        resolved = File.realpath(path)
        fail!("replacement read roots must be canonical") unless resolved == path
        protected = [@source, @destination, File.join(Dir.home, "Documents")]
        if resolved == File::SEPARATOR || protected.any? { |root| beneath?(root, resolved) || beneath?(resolved, root) }
          fail!("replacement read root overlaps protected continuation state")
        end
        resolved
      end

      allowlist = replacement["environment_allowlist"]
      valid_names = allowlist.is_a?(Array) && allowlist.uniq == allowlist &&
        allowlist.all? { |name| name.is_a?(String) && /\A[A-Z_][A-Z0-9_]*\z/.match?(name) }
      fail!("replacement environment_allowlist is invalid") unless valid_names
      checks = replacement["preflight_checks"]
      fail!("replacement preflight_checks must be a nonempty array") unless checks.is_a?(Array) && !checks.empty?
      fail!("replacement environment exceeds size bound") if JSON.generate(replacement).bytesize > 256 * 1024
      ids = checks.map do |check|
        fail!("replacement preflight check is malformed") unless check.is_a?(Hash) && check["environment_id"] == environment_id
        fail!("replacement preflight env exceeds its allowlist") unless check["env"].is_a?(Hash) && (check["env"].keys - allowlist).empty?
        check["id"]
      end
      fail!("replacement preflight IDs must be unique identifiers") unless ids.uniq == ids &&
        ids.all? { |id| id.is_a?(String) && Host::IDENTIFIER.match?(id) }

      old_environment = source_config.slice(*ENVIRONMENT_FIELDS)
      fail!("environment replacement did not change the frozen environment") if digest(old_environment) == digest(replacement)
      replacement
    rescue SystemCallError => error
      fail!("cannot resolve replacement environment: #{error.message}")
    end

    def verify_prior_continuation!(manifest)
      fail!("source continuation schema is unsupported") unless manifest["schema_version"] == LEGACY_SCHEMA_VERSION
      checks = {
        File.join("driver", "continuation", "source-config.json") => manifest["source_config_sha256"],
        File.join("driver", "continuation", "source-runtime.json") => manifest["source_runtime_sha256"],
        File.join("driver", "continuation", "source-preflight.json") => manifest["source_preflight_sha256"],
        File.join("driver", "config.json") => manifest["target_config_sha256"],
        File.join("driver", "preflight.json") => manifest["target_preflight_sha256"]
      }
      checks.each do |relative, expected|
        fail!("source continuation manifest is incomplete") unless expected.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(expected)
        fail!("source continuation evidence changed: #{relative}") unless Digest::SHA256.hexdigest(read_private(File.join(@source, relative))) == expected
      end
      source_manifest = parse_object(read_private(File.join(@source, manifest.fetch("source_manifest_path"))),
        "source continuation tree manifest")
      attributed = source_manifest.fetch("sha256")
      unless attributed == manifest["source_tree_sha256"] &&
             digest(source_manifest.reject { |key, _value| key == "sha256" }) == attributed
        fail!("source continuation tree attribution changed")
      end
      true
    rescue KeyError => error
      fail!("source continuation manifest is incomplete: #{error.message}")
    end

    def reject_old_environment_completion!(state)
      completed = state.fetch("work_orders").values.select { |order| order["status"] == "completed" }
      fail!("RC36 environment replacement refuses completed work orders with old check eligibility") unless completed.empty?
      unless state.fetch("reviews").empty? && state.fetch("assessments").empty? &&
             state.dig("milestone", "current_review_id").nil? &&
             !%w[review_ready closed deferred].include?(state.dig("milestone", "phase"))
        fail!("RC36 environment replacement refuses existing review or assessment evidence")
      end
    end

    def verify_preflight_records!(config, receipts)
      specs = config["preflight_checks"]
      fail!("source Driver preflight configuration is malformed") unless specs.is_a?(Array) && !specs.empty?
      fail!("source Driver preflight receipt set is malformed") unless receipts.length == specs.length
      fail!("source Driver preflight IDs changed") unless receipts.map { |entry| entry.is_a?(Hash) && entry["id"] } == specs.map { |spec| spec.is_a?(Hash) && spec["id"] }
      sentinel = File.join(@source, "driver", "isolation-sentinel.txt")
      read_private(sentinel)
      execution = Execution.new(
        project_root: config.fetch("project_root"), state_dir: @source,
        read_roots: config.fetch("read_roots", []),
        environment_allowlist: config.fetch("environment_allowlist", []),
        forbidden_read_path: sentinel, forbidden_write_path: sentinel
      )
      receipts.zip(specs).each do |entry, spec|
        descriptor = entry.fetch("execution").slice("receipt_path", "receipt_sha256")
        receipt = execution.verify_preflight!(descriptor, spec: spec)
        fail!("source Driver preflight did not pass") unless receipt["conclusion"] == "passed"
      end
    rescue KeyError => error
      fail!("source Driver preflight is incomplete: #{error.message}")
    end

    def verify_driver_requests!
      root = File.join(@source, "driver", "requests")
      return unless File.exist?(root)
      ensure_private_directory(root, "source Driver requests")
      Dir.children(root).sort.each do |name|
        fail!("source Driver request id is invalid") unless Host::IDENTIFIER.match?(name)
        directory = File.join(root, name)
        ensure_private_directory(directory, "source Driver request")
        children = Dir.children(directory).sort
        fail!("source Driver request has an unsafe layout") unless children == %w[receipt.json request.json]
        request = parse_object(read_private(File.join(directory, "request.json")), "source Driver request")
        receipt = parse_object(read_private(File.join(directory, "receipt.json")), "source Driver request receipt")
        fail!("source Driver request identity changed") unless request["request_id"] == name && receipt["request_id"] == name
        fail!("source Driver request operation changed") unless request["operation"].is_a?(String) && receipt["operation"] == request["operation"]
        fail!("source Driver request receipt is malformed") unless receipt["ok"].equal?(true) || receipt["ok"].equal?(false)
      end
    end

    def verify_host_records!(host)
      root = File.join(@source, "host-jobs")
      return {} unless File.exist?(root)
      ensure_private_directory(root, "source Host registry")
      statuses = {}
      Dir.children(root).sort.each do |name|
        path = File.join(root, name)
        if name == ".lock"
          read_private(path)
          next
        end
        ensure_private_directory(path, "source Host job")
        status = host.poll(job_id: name)
        fail!("duplicate Host job identity") if statuses.key?(status.fetch("job_id"))
        unless %w[succeeded failed running launch_unknown].include?(status["status"])
          fail!("source Host job has an invalid terminal status: #{name}")
        end
        verify_completed_job!(path, status) if %w[succeeded failed].include?(status["status"])
        statuses[status.fetch("job_id")] = status
      end
      statuses
    end

    def verify_completed_job!(path, status)
      completion = status.fetch("completion")
      if completion.key?("binding_digest") || completion.key?("check_plan_digest")
        fail!("Host completion binding changed") unless completion["binding_digest"] == status["binding_digest"]
        fail!("Host completion check plan changed") unless completion["check_plan_digest"] == status["check_plan_digest"]
      elsif status["status"] == "failed"
        fail!("failed Host completion is malformed") unless completion["error_class"].is_a?(String) &&
          completion["error"].is_a?(String) && completion["completed_at"].is_a?(String)
      end
      return unless status["status"] == "succeeded"

      fail!("successful Host job is missing a verified thread UUID") unless status["thread_id"] &&
        Host::UUID.match?(status["thread_id"]) && completion["thread_id"] == status["thread_id"]
      result_bytes = read_private(File.join(path, "result.json"), max_bytes: Host::MAX_RESULT_BYTES)
      fail!("Host result bytes changed after completion") unless Digest::SHA256.hexdigest(result_bytes) == completion["result_sha256"]
      Host.validate_result!(JSON.parse(result_bytes), role: status.fetch("role"))
    rescue JSON::ParserError => error
      fail!("invalid completed Host result: #{error.message}")
    end

    def request_record(source)
      environment = environment_transition_record(source)
      body = {
        "schema_version" => environment ? SCHEMA_VERSION : LEGACY_SCHEMA_VERSION,
        "source_state_dir" => @source,
        "destination_state_dir" => @destination,
        "source_run_id" => source.dig("config", "run_id"),
        "new_run_id" => @new_run_id,
        "source_kernel_root" => @source_kernel_root,
        "source_kernel_version" => source.fetch("source_kernel_version"),
        "source_kernel_revision" => source.fetch("source_kernel_revision"),
        "target_kernel_root" => source.fetch("target_kernel_root"),
        "target_kernel_revision" => source.fetch("target_kernel_revision"),
        "target_kernel_version" => source.fetch("target_kernel_version"),
        "target_version_verified" => source.fetch("target_version_verified"),
        "target_checkout_clean" => source.fetch("target_checkout_clean"),
        "production" => @production,
        "controller_stopped" => true,
        "supervisor_provenance" => @supervisor_provenance,
        "source_tree_sha256" => source.dig("tree", "sha256"),
        "source_cursor" => source.dig("store", "cursor"),
        "source_event_hash" => source.dig("store", "event_hash"),
        "legacy_controller_limit" => "The source Driver lock and explicit supervisor assertion establish the observed stop. This API cannot prove that an unrecorded legacy controller will not restart; both state roots are denied to new model jobs."
      }
      body["environment_transition"] = environment if environment
      body.merge("request_sha256" => digest(body))
    end

    def environment_transition_record(source)
      replacement = source["environment_replacement"]
      return nil unless replacement
      original = source.fetch("config").slice(*ENVIRONMENT_FIELDS)
      statuses = source.fetch("statuses")
      # Worker dispatch order, not identifier spelling, determines the latest
      # resumable attempt. Jobs outside that registry are historical extras.
      registered = source.fetch("runtime").fetch("jobs")
      ordered_ids = (statuses.keys.sort - registered) + registered
      jobs = ordered_ids.map do |job_id|
        status = statuses.fetch(job_id)
        status.slice("job_id", "role", "work_order_id", "revision", "claim_id", "status", "result_status", "thread_id")
      end
      {
        "source_environment" => original,
        "active_environment" => replacement,
        "source_environment_sha256" => digest(original),
        "active_environment_sha256" => digest(replacement),
        "source_environment_id" => original.fetch("environment_id"),
        "active_environment_id" => replacement.fetch("environment_id"),
        "historical_job_ids" => jobs.map { |job| job.fetch("job_id") },
        "historical_jobs" => jobs,
        "old_checks_eligible_for_new_claims" => false,
        "fresh_preflight_required" => true,
        "source_preflight_attribution" => "historical_only"
      }
    end

    def copy_tree(source, destination)
      Dir.mkdir(destination, 0o700)
      snapshot = snapshot_tree(source)
      snapshot.fetch("entries").each do |entry|
        relative = entry.fetch("path")
        from = File.join(source, relative)
        to = File.join(destination, relative)
        if entry["type"] == "directory"
          FileUtils.mkdir_p(to, mode: 0o700)
          File.chmod(0o700, to)
        else
          FileUtils.mkdir_p(File.dirname(to), mode: 0o700)
          bytes = read_private(from)
          fail!("source file changed while copying: #{relative}") unless bytes.bytesize == entry["bytes"] &&
            Digest::SHA256.hexdigest(bytes) == entry["sha256"]
          Host.atomic_write(to, bytes)
        end
      end
    end

    def derive_destination!(root, source, request)
      archive = continuation_archive(request)
      continuation = File.join(root, archive)
      Host.private_directory!(continuation)
      Host.atomic_write(File.join(continuation, "source-config.json"), source.fetch("config_bytes"))
      Host.atomic_write(File.join(continuation, "source-runtime.json"), source.fetch("runtime_bytes"))
      Host.atomic_write(File.join(continuation, "source-preflight.json"), source.fetch("preflight_bytes"))
      Host.atomic_json(File.join(continuation, "source-manifest.json"), source.fetch("tree"))

      config = JSON.parse(source.fetch("config_bytes"))
      config["run_id"] = @new_run_id
      config["forbidden_roots"] = (Array(config["forbidden_roots"]) + [@source, @destination]).uniq
      config["continuation"] = request.slice(
        "schema_version", "source_state_dir", "source_run_id", "source_kernel_revision",
        "source_kernel_version", "target_kernel_revision", "target_kernel_version", "source_tree_sha256", "source_cursor",
        "source_event_hash", "request_sha256"
      )
      environment = request["environment_transition"]
      if environment
        ENVIRONMENT_FIELDS.each { |field| config[field] = environment.fetch("active_environment").fetch(field) }
        config["continuation"]["environment_transition"] = compact_environment_transition(environment)
      end

      runtime = JSON.parse(source.fetch("runtime_bytes"))
      resume_job = safe_astra_resume_job(source.fetch("statuses"), runtime)
      runtime.delete("pending_dispatch")
      runtime.delete("pending_job_registration")
      runtime["orchestrator_job"] = nil
      runtime["resume_job"] = resume_job
      runtime["last_orchestrator_job"] = resume_job if environment
      runtime["observed_cursor"] = source.dig("store", "cursor")
      runtime["observed_technical_input_cursor"] = environment ? source.fetch("observed_technical_input_cursor") : 0
      runtime["orchestrator_technical_input_cursor"] = nil if environment
      runtime["feedback"] = [continuation_notice(request, resume_job)] + Array(runtime["feedback"])
      runtime["outcome"] = "active" if runtime["outcome"] == "engineering_stalled"
      runtime["idle_turns"] = 0 if source.dig("runtime", "outcome") == "engineering_stalled"
      runtime["continuation"] = request.slice("schema_version", "source_state_dir", "source_run_id", "request_sha256")
      if environment
        runtime["historical_environment"] = historical_environment(source, environment)
        runtime["jobs"] = []
        runtime["seen_jobs"] = []
        runtime["history"] = []
      end

      Host.atomic_json(File.join(root, "driver", "config.json"), config)
      Host.atomic_json(File.join(root, "driver", "runtime.json"), runtime)
    end

    def continuation_archive(request)
      request["schema_version"] == SCHEMA_VERSION ? RC37_CONTINUATION_DIRECTORY : CONTINUATION_DIRECTORY
    end

    def manifest_path(request)
      request["schema_version"] == SCHEMA_VERSION ? RC37_MANIFEST_PATH : MANIFEST_PATH
    end

    def compact_environment_transition(environment)
      environment.slice(
        "source_environment_id", "active_environment_id", "source_environment_sha256",
        "active_environment_sha256", "historical_job_ids", "old_checks_eligible_for_new_claims",
        "fresh_preflight_required"
      )
    end

    def historical_environment(source, environment)
      jobs = environment.fetch("historical_jobs")
      {
        "source_environment_id" => environment.fetch("source_environment_id"),
        "active_environment_id" => environment.fetch("active_environment_id"),
        "source_environment_sha256" => environment.fetch("source_environment_sha256"),
        "active_environment_sha256" => environment.fetch("active_environment_sha256"),
        "jobs" => jobs,
        "work_orders" => source.fetch("state").fetch("work_orders").values.sort_by { |order| order.fetch("id") }.map do |order|
          resumable = jobs.select do |job|
            job["role"] == "worker" && job["work_order_id"] == order["id"] &&
              job["revision"] == order["revision"] && job["claim_id"] == order["claim_id"] &&
              job["thread_id"] && Host::UUID.match?(job["thread_id"])
          end
          {
            "work_order_id" => order.fetch("id"), "status" => order.fetch("status"),
            "revision" => order.fetch("revision"), "claim_id" => order["claim_id"],
            "last_owner_id" => order["owner_id"],
            "required_action" => historical_work_order_action(order),
            "historical_resume_job_ids" => resumable.map { |job| job.fetch("job_id") }
          }
        end,
        "old_checks_eligible_for_new_claims" => false
      }
    end

    def historical_work_order_action(order)
      return "none_cancelled" if order["status"] == "cancelled"
      return "fresh_dispatch_under_active_environment" if order["status"] == "queued"
      "resume_same_claim_under_active_environment_or_release_then_rebind"
    end

    def prepare_target_preflight!(root, source)
      config = parse_object(read_private(File.join(root, "driver", "config.json")), "continued Driver configuration")
      return reverify_target_preflight!(root, config) unless source["environment_replacement"]

      sentinel = File.join(root, "driver", "isolation-sentinel.txt")
      execution = Execution.new(
        project_root: config.fetch("project_root"), state_dir: root,
        read_roots: config.fetch("read_roots", []),
        environment_allowlist: config.fetch("environment_allowlist", []),
        forbidden_read_path: sentinel, forbidden_write_path: sentinel
      )
      receipts = config.fetch("preflight_checks").map do |spec|
        descriptor = execution.preflight(spec: spec)
        fail!("replacement environment preflight reused historical evidence") unless descriptor["reused"] == false
        fail!("replacement environment preflight did not pass") unless descriptor["conclusion"] == "passed"
        { "id" => spec.fetch("id"), "execution" => descriptor }
      end
      Host.atomic_json(File.join(root, "driver", "preflight.json"), receipts)
      true
    rescue KeyError => error
      fail!("replacement environment preflight is incomplete: #{error.message}")
    end

    # Preflight identity intentionally excludes the state root: descriptors are
    # relative, and the copied receipt key authenticates the unchanged receipt.
    # Reverify the historical evidence under the destination policy. Do not call
    # Execution#preflight and mislabel its deterministic reuse as a fresh check.
    def reverify_target_preflight!(root, config)
      sentinel = File.join(root, "driver", "isolation-sentinel.txt")
      execution = Execution.new(
        project_root: config.fetch("project_root"), state_dir: root,
        read_roots: config.fetch("read_roots", []),
        environment_allowlist: config.fetch("environment_allowlist", []),
        forbidden_read_path: sentinel, forbidden_write_path: sentinel
      )
      receipts = parse_array(read_private(File.join(root, "driver", "preflight.json")), "continued Driver preflight")
      fail!("continued Driver preflight set changed") unless receipts.map { |entry| entry["id"] } ==
        config.fetch("preflight_checks").map { |spec| spec["id"] }
      receipts.zip(config.fetch("preflight_checks")).each do |entry, spec|
        descriptor = entry.fetch("execution").slice("receipt_path", "receipt_sha256")
        receipt = execution.verify_preflight!(descriptor, spec: spec)
        fail!("continued Driver historical preflight did not pass re-verification") unless receipt["conclusion"] == "passed"
      end
      true
    rescue KeyError => error
      fail!("continued Driver preflight is incomplete: #{error.message}")
    end

    def finalize_destination!(root, source, request)
      resume_job = safe_astra_resume_job(source.fetch("statuses"), source.fetch("runtime"))
      fresh = request["schema_version"] == SCHEMA_VERSION
      archive = continuation_archive(request)
      target_preflight = parse_array(read_private(File.join(root, "driver", "preflight.json")), "target preflight")
      manifest = request.merge(
        "created_at" => Time.now.utc.iso8601(6),
        "archive_root" => archive,
        "source_manifest_path" => File.join(archive, "source-manifest.json"),
        "source_config_sha256" => Digest::SHA256.hexdigest(source.fetch("config_bytes")),
        "source_runtime_sha256" => Digest::SHA256.hexdigest(source.fetch("runtime_bytes")),
        "source_preflight_sha256" => Digest::SHA256.hexdigest(source.fetch("preflight_bytes")),
        "target_config_sha256" => Digest::SHA256.file(File.join(root, "driver", "config.json")).hexdigest,
        "target_runtime_sha256" => Digest::SHA256.file(File.join(root, "driver", "runtime.json")).hexdigest,
        "target_preflight_sha256" => Digest::SHA256.file(File.join(root, "driver", "preflight.json")).hexdigest,
        "resumed_astra_job_id" => resume_job,
        "resumed_astra_thread_id" => resume_job && source.dig("statuses", resume_job, "thread_id"),
        "ledger_copied_unchanged" => true,
        "historical_receipts_copied_unchanged" => true,
        "source_preflight_is_historical" => true,
        "target_preflight_is_fresh" => fresh,
        "target_preflight_reverified_for_destination" => !fresh,
        "target_preflight_receipts" => target_preflight.map do |entry|
          entry.fetch("execution").slice("receipt_path", "receipt_sha256", "reused", "conclusion")
        end,
        "supervisor_input_cursor" => source.dig("supervisor_input", "cursor"),
        "acknowledged_supervisor_input_cursor" => source.fetch("observed_technical_input_cursor"),
        "fresh_orchestrator_projection_required" => true
      )
      Host.atomic_json(File.join(root, manifest_path(request)), manifest)
      private_tree!(root)
    end

    def safe_astra_resume_job(statuses, runtime)
      candidates = [runtime["orchestrator_job"], runtime["resume_job"]].compact.uniq
      candidates.each do |job_id|
        status = statuses[job_id]
        next unless status && status["role"] == "orchestrator" &&
          %w[succeeded failed].include?(status["status"]) && status["thread_id"] && Host::UUID.match?(status["thread_id"])
        return job_id
      end
      nil
    end

    def continuation_notice(request, resume_job)
      {
        "kind" => "versioned_run_continuation",
        "ok" => true,
        "message" => "#{request.fetch('target_kernel_version')} continuation: project the copied ledger and receipts afresh. Do not replay requests from any copied Astra result. Preserve operator decisions, authority, work state, and consumed turn budget. Historical environment jobs and checks are ineligible for new claims; commission fresh work under the active environment.",
        "source_run_id" => request["source_run_id"],
        "source_kernel_version" => request["source_kernel_version"],
        "source_kernel_revision" => request["source_kernel_revision"],
        "target_kernel_revision" => request["target_kernel_revision"],
        "resume_job_id" => resume_job
      }
    end

    def verify_idempotent_destination!(request)
      path = File.join(@destination, manifest_path(request))
      fail!("destination already exists and is not this continuation") unless File.file?(path) && !File.symlink?(path)
      manifest = parse_object(read_private(path), "continuation manifest")
      unless manifest["request_sha256"] == request["request_sha256"]
        changed = request.keys.reject { |key| key == "request_sha256" || manifest[key] == request[key] }
        fail!("destination already exists for a conflicting continuation (changed: #{changed.sort.join(', ')})")
      end
      verify_manifest_files!(@destination, manifest)
      Store.new(@destination).verify!
      verify_destination_preflight!(@destination)
      manifest
    end

    def verify_created_destination!(request)
      manifest = verify_idempotent_destination!(request)
      Store.new(@destination).verify!
      manifest
    end

    def verify_destination_preflight!(root)
      config = parse_object(read_private(File.join(root, "driver", "config.json")), "continued Driver configuration")
      sentinel = File.join(root, "driver", "isolation-sentinel.txt")
      execution = Execution.new(
        project_root: config.fetch("project_root"), state_dir: root,
        read_roots: config.fetch("read_roots", []),
        environment_allowlist: config.fetch("environment_allowlist", []),
        forbidden_read_path: sentinel, forbidden_write_path: sentinel
      )
      receipts = parse_array(read_private(File.join(root, "driver", "preflight.json")), "continued Driver preflight")
      fail!("continued Driver preflight set changed") unless receipts.map { |entry| entry["id"] } ==
        config.fetch("preflight_checks").map { |spec| spec["id"] }
      receipts.zip(config.fetch("preflight_checks")).each do |entry, spec|
        receipt = execution.verify_preflight!(entry.fetch("execution").slice("receipt_path", "receipt_sha256"), spec: spec)
        fail!("continued Driver preflight did not pass verification") unless receipt["conclusion"] == "passed"
      end
      true
    rescue KeyError => error
      fail!("continued Driver preflight is incomplete: #{error.message}")
    end

    def verify_manifest_files!(root, manifest)
      archive = manifest.fetch("archive_root", CONTINUATION_DIRECTORY)
      checks = {
        File.join(archive, "source-config.json") => manifest["source_config_sha256"],
        File.join(archive, "source-runtime.json") => manifest["source_runtime_sha256"],
        File.join(archive, "source-preflight.json") => manifest["source_preflight_sha256"],
        File.join("driver", "config.json") => manifest["target_config_sha256"],
        File.join("driver", "runtime.json") => manifest["target_runtime_sha256"],
        File.join("driver", "preflight.json") => manifest["target_preflight_sha256"]
      }
      checks.each do |relative, expected|
        fail!("continuation manifest is incomplete") unless expected.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(expected)
        bytes = read_private(File.join(root, relative))
        fail!("continued state differs from its manifest: #{relative}") unless Digest::SHA256.hexdigest(bytes) == expected
      end
      source_manifest = parse_object(
        read_private(File.join(root, manifest.fetch("source_manifest_path"))),
        "source tree manifest"
      )
      manifest_digest = source_manifest.fetch("sha256")
      fail!("source tree manifest attribution changed") unless manifest_digest == manifest["source_tree_sha256"] &&
        digest(source_manifest.reject { |key, _value| key == "sha256" }) == manifest_digest
      source_manifest.fetch("entries").each do |entry|
        next unless entry["type"] == "file"
        relative = entry.fetch("path")
        target = case relative
                 when File.join("driver", "config.json")
                   File.join(root, archive, "source-config.json")
                 when File.join("driver", "runtime.json")
                   File.join(root, archive, "source-runtime.json")
                 when File.join("driver", "preflight.json")
                   File.join(root, archive, "source-preflight.json")
                 else File.join(root, relative)
                 end
        bytes = read_private(target)
        fail!("historical continued evidence changed: #{relative}") unless bytes.bytesize == entry["bytes"] &&
          Digest::SHA256.hexdigest(bytes) == entry["sha256"]
      end
    rescue KeyError => error
      fail!("continuation manifest is incomplete: #{error.message}")
    end

    def verify_source_unchanged!(expected)
      actual = snapshot_tree(@source)
      fail!("source state changed while it was being copied") unless actual == expected
    end

    def snapshot_tree(root)
      entries = []
      total = 0
      walk(root) do |path, relative, stat|
        fail!("state tree has too many entries") if entries.length >= MAX_ENTRIES
        if stat.directory?
          entries << { "path" => relative, "type" => "directory" } unless relative.empty?
        elsif stat.file?
          fail!("state file is not private: #{relative}") unless (stat.mode & 0o077).zero?
          fail!("state file exceeds continuation bound: #{relative}") if stat.size > MAX_FILE_BYTES
          total += stat.size
          fail!("state tree exceeds continuation byte bound") if total > MAX_TOTAL_BYTES
          entries << { "path" => relative, "type" => "file", "bytes" => stat.size,
                       "sha256" => Digest::SHA256.file(path).hexdigest }
        else
          fail!("state tree contains a symlink or special file: #{relative}")
        end
      end
      body = { "entries" => entries, "file_count" => entries.count { |item| item["type"] == "file" }, "total_bytes" => total }
      body.merge("sha256" => digest(body))
    end

    def walk(root, relative = "", &block)
      path = relative.empty? ? root : File.join(root, relative)
      stat = File.lstat(path)
      fail!("state tree contains a symlink: #{relative}") if stat.symlink?
      yield(path, relative, stat)
      return unless stat.directory?
      fail!("state directory is not private: #{relative}") unless (stat.mode & 0o077).zero?
      Dir.children(path).sort.each { |name| walk(root, relative.empty? ? name : File.join(relative, name), &block) }
    end

    def private_tree!(root)
      walk(root) do |path, _relative, stat|
        File.chmod(stat.directory? ? 0o700 : 0o600, path)
      end
    end

    def verify_git_checkout!(root, expected: nil, require_clean:, scope:)
      top = git(root, "rev-parse", "--show-toplevel").strip
      fail!("#{scope} root is not the Git top-level") unless File.realpath(top) == root
      revision = git(root, "rev-parse", "HEAD").strip
      fail!("#{scope} revision is not a full commit") unless GIT_REVISION.match?(revision)
      fail!("#{scope} does not match the declared revision") if expected && revision != expected
      status = git(root, "status", "--porcelain=v1", "--untracked-files=all")
      clean = status.empty?
      fail!("#{scope} checkout must be clean") if require_clean && !clean
      expected || { "revision" => revision, "clean" => clean }
    end

    def source_kernel_version(revision)
      playbook = git(@source_kernel_root, "show", "#{revision}:playbooks/hrm-interaction-kernel.md")
      version = TRANSITIONS.keys.find do |candidate|
        playbook.lines.first(12).any? do |line|
          title = line.chomp
          title == "title: #{candidate}" || title.start_with?("title: #{candidate} -")
        end
      end
      fail!("declared source pin is not a supported continuation source") unless version
      version
    end

    def verify_target_kernel_version!(root, revision, expected_version, required:)
      playbook = git(root, "show", "#{revision}:playbooks/hrm-interaction-kernel.md")
      expected = "title: #{expected_version}"
      verified = playbook.lines.first(12).any? do |line|
        title = line.chomp
        title == expected || title.start_with?("#{expected} -")
      end
      fail!("executing target commit does not declare #{expected_version}") if required && !verified
      verified
    end

    def git(root, *args)
      stdout, stderr, status = Open3.capture3("git", "-C", root, *args)
      fail!("cannot verify Git checkout: #{stderr.strip}") unless status.success?
      stdout
    end

    def canonical_existing_directory(value, label)
      fail!("#{label} must be an absolute path") unless value.is_a?(String) && Pathname.new(value).absolute?
      fail!("#{label} itself may not be a symlink") if File.symlink?(value)
      resolved = File.realpath(value)
      fail!("#{label} must be a directory") unless File.directory?(resolved)
      resolved
    rescue SystemCallError => error
      fail!("cannot resolve #{label}: #{error.message}")
    end

    def canonical_destination(value)
      fail!("destination state directory must be an absolute path") unless value.is_a?(String) && Pathname.new(value).absolute?
      expanded = File.expand_path(value)
      fail!("destination state directory itself may not be a symlink") if File.symlink?(expanded)
      return File.realpath(expanded) if File.exist?(expanded)
      ancestor = expanded
      until File.exist?(ancestor)
        parent = File.dirname(ancestor)
        fail!("cannot resolve destination parent") if parent == ancestor
        ancestor = parent
      end
      File.join(File.realpath(ancestor), Pathname.new(expanded).relative_path_from(Pathname.new(ancestor)).to_s)
    rescue SystemCallError, ArgumentError => error
      fail!("cannot resolve destination state directory: #{error.message}")
    end

    def ensure_private_directory(path, label)
      fail!("#{label} is a symlink") if File.symlink?(path)
      stat = File.stat(path)
      fail!("#{label} must be a private directory") unless stat.directory? && (stat.mode & 0o077).zero?
    rescue SystemCallError => error
      fail!("cannot read #{label}: #{error.message}")
    end

    def read_private(path, max_bytes: MAX_FILE_BYTES)
      fail!("unsafe symlink file: #{path}") if File.symlink?(path)
      stat = File.stat(path)
      fail!("expected a private regular file: #{path}") unless stat.file? && (stat.mode & 0o077).zero?
      fail!("file exceeds continuation bound: #{path}") if stat.size > max_bytes
      File.binread(path)
    rescue SystemCallError => error
      fail!("cannot read continuation input: #{error.message}")
    end

    def parse_object(bytes, label)
      value = JSON.parse(bytes)
      fail!("#{label} must be an object") unless value.is_a?(Hash)
      value
    rescue JSON::ParserError => error
      fail!("#{label} is invalid JSON: #{error.message}")
    end

    def parse_array(bytes, label)
      value = JSON.parse(bytes)
      fail!("#{label} must be an array") unless value.is_a?(Array)
      value
    rescue JSON::ParserError => error
      fail!("#{label} is invalid JSON: #{error.message}")
    end

    def string_array?(value)
      value.is_a?(Array) && value.all? { |item| item.is_a?(String) && Host::IDENTIFIER.match?(item) }
    end

    def beneath?(path, root)
      path == root || path.start_with?(root + File::SEPARATOR)
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
    end

    def canonical(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end

    def fsync_directory(path)
      File.open(path, File::RDONLY) { |directory| directory.fsync }
    rescue Errno::EINVAL, Errno::EISDIR
      nil
    end

    def fail!(message)
      raise HrmKernel::Error, message
    end
  end
end
