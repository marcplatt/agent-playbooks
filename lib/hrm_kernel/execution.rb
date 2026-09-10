# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "openssl"
require "open3"
require "pathname"
require "rbconfig"
require "securerandom"
require "timeout"

require_relative "error"

module HrmKernel
  class Execution
    RECEIPT_SCHEMA = "ap-hrm-native-check-receipt/1"
    PREFLIGHT_RECEIPT_SCHEMA = "ap-hrm-execution-preflight-receipt/1"
    CANDIDATE_SCHEMA = "ap-hrm-git-candidate/1"
    KEY_NAME = ".execution-receipt-key"
    EXECUTION_DIRECTORY = "execution"
    MAX_OUTPUT_BYTES = 16 * 1024 * 1024
    READ_CHUNK_BYTES = 16 * 1024
    RUN_ROOT_TOKEN = "{run_root}"
    CANDIDATE_ROOT_TOKEN = "{candidate_root}"
    REPOSITORY_VIEW_SCHEMA = "ap-hrm-isolated-head-candidate/1"
    MAX_REPOSITORY_OBJECTS = 20_000
    MAX_REPOSITORY_OBJECT_BYTES = 256 * 1024 * 1024
    SENSITIVE_BASENAME = /\A(?:\.env(?:\..*)?|credentials[^\/]*\.json|[^\/]*\.(?:db|sqlite|sqlite3|pem|key))\z/i
    SYSTEM_READ_ROOTS = [
      "/usr/bin",
      "/usr/lib",
      "/usr/share/zoneinfo",
      "/private/var/db/timezone",
      "/System/Library",
      "/Library/Apple",
      "/Library/Ruby",
      "/private/var/db/dyld",
      "/private/var/select",
      "/var/select",
      "/dev/null",
      "/dev/urandom"
    ].freeze

    attr_reader :project_root, :state_dir

    def initialize(project_root:, state_dir:, read_roots: [], environment_allowlist: [],
                   forbidden_read_path: nil, forbidden_write_path: nil,
                   repository_view: nil,
                   sandbox_executable: "/usr/bin/sandbox-exec")
      @project_root = canonical_directory!(project_root, "project_root")
      @state_dir = canonical_private_directory!(state_dir)
      @read_roots = Array(read_roots).map { |path| canonical_read_root!(path) }.uniq.freeze
      @environment_allowlist = Array(environment_allowlist).map do |name|
        fail!("environment allowlist entries must be variable names") unless name.is_a?(String) && name.match?(/\A[A-Z_][A-Z0-9_]*\z/)
        name
      end.uniq.freeze
      @forbidden_read_path = optional_canonical_file(forbidden_read_path, "forbidden_read_path")
      @forbidden_write_path = optional_canonical_file(forbidden_write_path, "forbidden_write_path")
      @sandbox_executable = canonical_executable!(sandbox_executable, "sandbox_executable")
      @repository_view = validate_repository_view!(repository_view)
      if @repository_view && @read_roots.any? { |root| within?(@project_root, root) || within?(root, @project_root) }
        fail!("isolated repository checks may not grant the source project as a dependency root")
      end
      ensure_supported_platform!
      @sensitive_existing_files = discover_sensitive_existing_files.freeze
      prepare_execution_directory!
    end

    def capture_candidate(work_order:, milestone:, claim_id:, revision:, requirement_revisions:, check_plan:,
                          authorized_paths: nil)
      order = stringify_hash!(work_order, "work_order")
      milestone = stringify_hash!(milestone, "milestone")
      fail!("claim_id must be a non-empty string") unless claim_id.is_a?(String) && !claim_id.empty?
      fail!("revision must match the work order") unless revision.is_a?(Integer) && revision == order["revision"]
      unless requirement_revisions == order["requirement_revisions"] && requirement_revisions.is_a?(Hash)
        fail!("requirement revisions do not match the work order")
      end
      validate_check_plan!(check_plan, order)

      changes = git_changes
      fail!("implementation candidate has no Git changes") if changes.empty?
      allowed_paths = authorized_paths.nil? ? Array(order["paths"]) : Array(authorized_paths)
      validate_change_scope!(changes, allowed_paths)
      has_deliverable = Array(order["paths"]).any? do |declared|
        changes.any? { |entry| path_matches?(entry["path"], declared) }
      end
      # Paths bound write authority; they are not a quota of files to modify.
      # Unchanged dependencies may remain declared without manufacturing edits.
      fail!("work order has no candidate changes in its declared paths") unless has_deliverable
      binding = {
        "work_order_id" => order.fetch("id"),
        "claim_id" => claim_id,
        "revision" => revision,
        "requirement_revisions" => canonical_value(requirement_revisions),
        "work_order_contract_digest" => self.class.contract_digest(milestone, order),
        "check_plan_digest" => check_plan_digest(check_plan),
        "authorized_paths" => allowed_paths.sort
      }
      manifest = {
        "schema_version" => CANDIDATE_SCHEMA,
        "project_root" => @project_root,
        "head_sha" => git_output("rev-parse", "HEAD").strip,
        "head_tree" => git_output("rev-parse", "HEAD^{tree}").strip,
        "changes" => changes,
        "binding" => binding,
        "check_plan" => canonical_value(check_plan),
        "executable_identities" => executable_identities(check_plan),
        "execution_policy" => policy_manifest
      }
      manifest["candidate_digest"] = digest(manifest)
      manifest
    end

    def run(spec:, binding:, candidate:)
      candidate = stringify_hash!(candidate, "candidate")
      binding = stringify_hash!(binding, "binding")
      spec = stringify_hash!(spec, "execution spec")
      verify_candidate_manifest!(candidate, exact: true)
      fail!("execution binding does not match candidate") unless binding == candidate["binding"]
      validate_spec_against_plan!(spec, candidate)

      run_id = execution_id(spec, binding, candidate)
      run_root = prepare_run_root!(run_id)
      receipt_path = File.join(run_root, "receipt.json")
      if File.exist?(receipt_path)
        descriptor = receipt_descriptor(receipt_path)
        receipt = verify_receipt!(descriptor, binding: binding, candidate: candidate, current_exact: true)
        fail!("an inconclusive receipt cannot be reused") unless %w[passed failed].include?(receipt["conclusion"])
        return descriptor.merge("conclusion" => receipt["conclusion"], "reused" => true)
      end

      repository = prepare_repository_view!(run_root, candidate)
      execution_root = repository ? repository.fetch("root") : @project_root
      materialized_spec = materialize_spec(spec, run_root, execution_root)
      validate_configuration_paths!(materialized_spec, run_root)
      profile = sandbox_profile(run_root, project_root: execution_root)
      isolation = preflight_isolation!(profile, run_root, project_root: execution_root)
      result = execute_process(materialized_spec, profile, run_root)
      privatize_run_scratch!(run_root, except: repository && repository.fetch("root"))
      verify_candidate_manifest!(candidate, exact: true)
      verify_repository_view!(repository.fetch("receipt"), candidate) if repository

      stdout_path = write_private_exclusive!(run_root, "stdout.bin", result.delete("stdout"))
      stderr_path = write_private_exclusive!(run_root, "stderr.bin", result.delete("stderr"))
      conclusion = if result["output_limit_exceeded"]
                     "output_limit_exceeded"
                   elsif result["timed_out"]
                     "timed_out"
                   elsif result["exit_status"].zero?
                     "passed"
                   else
                     "failed"
                   end
      unsigned = {
        "schema_version" => RECEIPT_SCHEMA,
        "receipt_id" => run_id,
        "binding" => binding,
        "check_id" => spec.fetch("id"),
        "environment_id" => spec.fetch("environment_id"),
        "repository_view" => repository && repository.fetch("receipt"),
        "candidate_digest" => candidate.fetch("candidate_digest"),
        "candidate" => candidate,
        "execution_spec_digest" => digest(spec),
        "sandbox_policy_digest" => digest(profile),
        "preflight" => isolation,
        "conclusion" => conclusion,
        "exit_status" => result.fetch("exit_status"),
        "timed_out" => result.fetch("timed_out"),
        "output_limit_exceeded" => result.fetch("output_limit_exceeded"),
        "duration_milliseconds" => result.fetch("duration_milliseconds"),
        "stdout" => private_log_descriptor(stdout_path),
        "stderr" => private_log_descriptor(stderr_path)
      }
      receipt = unsigned.merge("authentication" => receipt_authentication(unsigned))
      write_private_exclusive!(run_root, "receipt.json", canonical_json(receipt) << "\n")
      descriptor = receipt_descriptor(receipt_path)
      descriptor.merge("conclusion" => conclusion, "reused" => false)
    end

    # Executes an explicitly declared environment smoke check without requiring
    # a work order, Git changes, or a worker claim. Callers freeze this receipt
    # before dispatching a native worker; it must never stand in for a product
    # check or be inferred from one.
    def preflight(spec:)
      spec = stringify_hash!(spec, "preflight spec")
      validate_execution_spec!(spec)
      run_id = digest({
        "kind" => "environment_preflight",
        "declared_environment" => declared_environment(spec),
        "execution_policy" => policy_manifest,
        "executable_identity" => executable_identity(spec.fetch("argv").first)
      })
      run_root = prepare_run_root!("preflight-#{run_id}")
      receipt_path = File.join(run_root, "preflight-receipt.json")
      if File.exist?(receipt_path)
        descriptor = receipt_descriptor(receipt_path)
        receipt = verify_preflight!(descriptor, spec: spec)
        return descriptor.merge("conclusion" => receipt["conclusion"], "reused" => true)
      end

      materialized_spec = materialize_spec(spec, run_root)
      validate_configuration_paths!(materialized_spec, run_root)
      profile = sandbox_profile(run_root)
      isolation = preflight_isolation!(profile, run_root)
      result = execute_process(materialized_spec, profile, run_root)
      privatize_run_scratch!(run_root)
      startup_marker = spec["startup_success_marker"]
      startup_completed = startup_marker.nil? ? nil : result.fetch("stdout").include?(startup_marker)
      stdout_path = write_private_exclusive!(run_root, "preflight-stdout.bin", result.delete("stdout"))
      stderr_path = write_private_exclusive!(run_root, "preflight-stderr.bin", result.delete("stderr"))
      conclusion = preflight_conclusion(result, startup_completed: startup_completed)
      unsigned = {
        "schema_version" => PREFLIGHT_RECEIPT_SCHEMA,
        "receipt_id" => run_id,
        "check_id" => spec.fetch("id"),
        "environment_id" => spec.fetch("environment_id"),
        "declared_environment" => declared_environment(spec),
        "declared_environment_digest" => digest(declared_environment(spec)),
        "execution_policy" => policy_manifest,
        "execution_policy_digest" => digest(profile),
        "executable_identity" => executable_identity(spec.fetch("argv").first),
        "isolation" => isolation,
        "startup_completed" => startup_completed,
        "conclusion" => conclusion,
        "exit_status" => result.fetch("exit_status"),
        "term_signal" => result.fetch("term_signal"),
        "timed_out" => result.fetch("timed_out"),
        "output_limit_exceeded" => result.fetch("output_limit_exceeded"),
        "duration_milliseconds" => result.fetch("duration_milliseconds"),
        "stdout" => private_log_descriptor(stdout_path),
        "stderr" => private_log_descriptor(stderr_path)
      }
      receipt = unsigned.merge("authentication" => receipt_authentication(unsigned))
      write_private_exclusive!(run_root, "preflight-receipt.json", canonical_json(receipt) << "\n")
      receipt_descriptor(receipt_path).merge("conclusion" => conclusion, "reused" => false)
    rescue Errno::ENOENT, Errno::EACCES => e
      fail!("environment preflight failed to start: #{e.message}")
    end

    def verify_preflight!(descriptor, spec: nil)
      descriptor = stringify_hash!(descriptor, "preflight receipt descriptor")
      expected_keys!(descriptor, %w[receipt_path receipt_sha256])
      path = safe_state_file!(descriptor.fetch("receipt_path"))
      receipt = JSON.parse(read_private_file!(path, descriptor.fetch("receipt_sha256")))
      fail!("preflight receipt must be a JSON object") unless receipt.is_a?(Hash)
      authentication = receipt["authentication"]
      fail!("preflight receipt authentication is missing") unless authentication.is_a?(Hash)
      unsigned = receipt.reject { |key, _| key == "authentication" }
      expected_authentication = receipt_authentication(unsigned)
      fail!("preflight receipt authentication failed") unless secure_equal?(authentication["hmac_sha256"], expected_authentication["hmac_sha256"])
      fail!("preflight receipt schema is unsupported") unless receipt["schema_version"] == PREFLIGHT_RECEIPT_SCHEMA
      fail!("preflight execution policy changed") unless receipt["execution_policy"] == policy_manifest
      unless receipt["declared_environment_digest"] == digest(receipt.fetch("declared_environment"))
        fail!("preflight declared environment digest mismatch")
      end
      fail!("preflight executable identity drifted") unless receipt["executable_identity"] == executable_identity(receipt.dig("declared_environment", "argv", 0))
      if spec
        spec = stringify_hash!(spec, "preflight spec")
        validate_execution_spec!(spec)
        fail!("preflight declared environment changed") unless receipt["declared_environment"] == declared_environment(spec)
      end
      stdout = verify_private_log!(receipt.fetch("stdout"))
      verify_private_log!(receipt.fetch("stderr"))
      marker = receipt.dig("declared_environment", "startup_success_marker")
      expected_startup = marker.nil? ? nil : stdout.include?(marker)
      fail!("preflight startup phase was not derived from output") unless receipt["startup_completed"] == expected_startup
      unless receipt["conclusion"] == preflight_conclusion(receipt, startup_completed: expected_startup)
        fail!("preflight conclusion was not derived from process exit")
      end
      receipt
    rescue JSON::ParserError => e
      fail!("preflight receipt contains invalid JSON: #{e.message}")
    end

    def prepare_run_root(spec:, binding:, candidate:)
      candidate = stringify_hash!(candidate, "candidate")
      binding = stringify_hash!(binding, "binding")
      spec = stringify_hash!(spec, "execution spec")
      verify_candidate_manifest!(candidate, exact: true)
      fail!("execution binding does not match candidate") unless binding == candidate["binding"]
      validate_spec_against_plan!(spec, candidate)
      prepare_run_root!(execution_id(spec, binding, candidate))
    end

    def verify_receipt!(descriptor, binding: nil, expected_binding: nil, candidate: nil, current_exact: false)
      descriptor = stringify_hash!(descriptor, "receipt descriptor")
      expected_keys!(descriptor, %w[receipt_path receipt_sha256])
      path = safe_state_file!(descriptor.fetch("receipt_path"))
      contents = read_private_file!(path, descriptor.fetch("receipt_sha256"))
      receipt = JSON.parse(contents)
      fail!("native receipt must be a JSON object") unless receipt.is_a?(Hash)
      authentication = receipt["authentication"]
      fail!("native receipt authentication is missing") unless authentication.is_a?(Hash)
      unsigned = receipt.reject { |key, _| key == "authentication" }
      expected_authentication = receipt_authentication(unsigned)
      fail!("native receipt authentication failed") unless secure_equal?(authentication["hmac_sha256"], expected_authentication["hmac_sha256"])
      fail!("native receipt schema is unsupported") unless receipt["schema_version"] == RECEIPT_SCHEMA
      verify_repository_view_receipt!(receipt["repository_view"], candidate || receipt["candidate"])
      fail!("native receipt binding mismatch") if binding && receipt["binding"] != binding
      if expected_binding
        expected_binding.each do |key, value|
          fail!("native receipt binding mismatch for #{key}") unless receipt.dig("binding", key) == value
        end
      end
      candidate ||= receipt["candidate"]
      fail!("native receipt candidate is missing") unless candidate.is_a?(Hash)
      fail!("native receipt candidate mismatch") unless receipt["candidate_digest"] == candidate["candidate_digest"]
      plan = candidate["check_plan"]
      spec = plan.is_a?(Hash) && Array(plan["checks"]).find { |entry| entry["id"] == receipt["check_id"] }
      fail!("native receipt check is absent from its frozen plan") unless spec.is_a?(Hash)
      fail!("native receipt environment differs from its frozen check") unless receipt["environment_id"] == spec["environment_id"]
      fail!("native receipt execution spec mismatch") unless receipt["execution_spec_digest"] == digest(spec)
      frozen_plan_digest = digest({ "check_plan" => plan, "execution_policy" => candidate["execution_policy"] })
      fail!("native receipt check plan mismatch") unless receipt.dig("binding", "check_plan_digest") == frozen_plan_digest
      expected_conclusion = if receipt["output_limit_exceeded"]
                              "output_limit_exceeded"
                            elsif receipt["timed_out"]
                              "timed_out"
                            elsif receipt["exit_status"] == 0
                              "passed"
                            else
                              "failed"
                            end
      fail!("native receipt conclusion was not derived from process exit") unless receipt["conclusion"] == expected_conclusion
      verify_private_log!(receipt.fetch("stdout"))
      verify_private_log!(receipt.fetch("stderr"))
      verify_candidate_manifest!(candidate, exact: current_exact)
      receipt
    rescue JSON::ParserError => e
      fail!("native receipt contains invalid JSON: #{e.message}")
    end

    def self.contract_digest(milestone, work_order)
      milestone_fields = %w[id revision mode outcome allowed_paths requirements]
      order_fields = %w[id revision objective requirement_ids requirement_revisions paths check_ids effect_class]
      payload = {
        "milestone" => milestone_fields.each_with_object({}) { |key, memo| memo[key] = milestone[key] if milestone.key?(key) },
        "work_order" => order_fields.each_with_object({}) { |key, memo| memo[key] = work_order[key] if work_order.key?(key) }
      }
      Digest::SHA256.hexdigest(JSON.generate(canonical(payload)))
    end

    def self.canonical(value)
      case value
      when Hash
        value.keys.sort.each_with_object({}) { |key, memo| memo[key] = canonical(value[key]) }
      when Array
        value.map { |entry| canonical(entry) }
      else
        value
      end
    end

    private

    def ensure_supported_platform!
      fail!("native execution requires macOS sandbox-exec") unless RUBY_PLATFORM.include?("darwin")
      fail!("native execution requires sandbox-exec") unless File.file?(@sandbox_executable) && File.executable?(@sandbox_executable)
    end

    def prepare_execution_directory!
      path = File.join(@state_dir, EXECUTION_DIRECTORY)
      if File.exist?(path) || File.symlink?(path)
        stat = File.lstat(path)
        fail!("execution directory must be a private regular directory") unless stat.directory? && !stat.symlink? && stat.uid == Process.uid && (stat.mode & 0o777) == 0o700
      else
        Dir.mkdir(path, 0o700)
      end
      @execution_directory = File.realpath(path)
      key_path = File.join(@state_dir, KEY_NAME)
      unless File.exist?(key_path)
        File.open(key_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.binmode
          file.write(SecureRandom.random_bytes(32))
          file.flush
          file.fsync
        end
      end
      stat = File.lstat(key_path)
      fail!("execution receipt key must be owner-private") unless stat.file? && !stat.symlink? && stat.uid == Process.uid && (stat.mode & 0o777) == 0o600
      @receipt_key_path = key_path
    end

    def prepare_run_root!(run_id)
      path = File.join(@execution_directory, run_id)
      if File.exist?(path) || File.symlink?(path)
        stat = File.lstat(path)
        fail!("execution run root is unsafe") unless stat.directory? && !stat.symlink? && stat.uid == Process.uid && (stat.mode & 0o777) == 0o700
      else
        Dir.mkdir(path, 0o700)
      end
      File.realpath(path)
    end

    def validate_check_plan!(plan, order)
      plan = stringify_hash!(plan, "check_plan")
      fail!("check plan environment_id is required") unless plan["environment_id"].is_a?(String) && !plan["environment_id"].empty?
      checks = plan["checks"]
      fail!("check plan checks must be an array") unless checks.is_a?(Array)
      ids = checks.map do |spec|
        validate_execution_spec!(stringify_hash!(spec, "execution spec"))
        spec["id"]
      end
      fail!("check plan must exactly match work order checks") unless ids.sort == Array(order["check_ids"]).sort && ids.uniq.length == ids.length
    end

    def validate_spec_against_plan!(spec, candidate)
      validate_execution_spec!(spec)
      plan = candidate.fetch("check_plan")
      expected = Array(plan["checks"]).find { |entry| entry["id"] == spec["id"] }
      fail!("execution spec is not in the frozen check plan") unless expected == spec
      fail!("execution environment changed") unless spec["environment_id"] == plan["environment_id"]
      fail!("check plan digest changed") unless candidate.dig("binding", "check_plan_digest") == check_plan_digest(plan)
    end

    def validate_execution_spec!(spec)
      expected_keys!(spec, %w[id environment_id argv env cwd timeout_seconds configuration_paths], %w[max_output_bytes startup_success_marker])
      fail!("check id is invalid") unless spec["id"].is_a?(String) && !spec["id"].empty?
      fail!("environment_id is invalid") unless spec["environment_id"].is_a?(String) && !spec["environment_id"].empty?
      argv = spec["argv"]
      fail!("argv must be a non-empty string array") unless argv.is_a?(Array) && !argv.empty? && argv.all? { |entry| entry.is_a?(String) && !entry.include?("\0") }
      canonical_executable!(argv.first, "argv executable")
      env = stringify_hash!(spec["env"], "execution env")
      fail!("execution env exceeds the explicit allowlist") unless (env.keys - @environment_allowlist).empty?
      env.each do |name, value|
        fail!("execution environment values must be strings") unless value.is_a?(String) && !value.include?("\0")
      end
      if @repository_view
        repository_environment.each do |name, value|
          fail!("repository check environment #{name} is not pinned") unless env[name] == value
        end
      end
      cwd = canonical_directory!(spec["cwd"], "execution cwd")
      fail!("execution cwd must be within project_root") unless within?(cwd, @project_root)
      timeout = spec["timeout_seconds"]
      fail!("timeout_seconds must be a positive integer") unless timeout.is_a?(Integer) && timeout.positive? && timeout <= 3600
      maximum = spec.fetch("max_output_bytes", MAX_OUTPUT_BYTES)
      fail!("max_output_bytes is invalid") unless maximum.is_a?(Integer) && maximum.positive? && maximum <= MAX_OUTPUT_BYTES
      paths = spec["configuration_paths"]
      fail!("configuration_paths must be an array") unless paths.is_a?(Array) && paths.all? { |path| path.is_a?(String) }
      marker = spec["startup_success_marker"]
      if marker && (!marker.is_a?(String) || marker.empty? || marker.bytesize > 256)
        fail!("startup_success_marker must be a short non-empty string")
      end
      true
    end

    def validate_configuration_paths!(spec, run_root)
      Array(spec["configuration_paths"]).each do |path|
        fail!("configuration paths must be absolute after {run_root} expansion; use configuration_paths: [] for project configuration and select it through argv") unless Pathname.new(path).absolute?
        expanded = File.expand_path(path)
        fail!("configuration paths must remain in the disposable run root; project files such as pyproject.toml belong in argv with configuration_paths: [], not in this scratch-only field") unless within?(expanded, run_root)
        stat = File.lstat(expanded)
        fail!("configuration path must not be a symlink") if stat.symlink?
        fail!("configuration path must be a regular file or directory") unless stat.file? || stat.directory?
      end
    rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => e
      fail!("configuration path cannot be accessed: #{e.message}")
    end

    def policy_manifest
      manifest = {
        "runner" => "sandbox-exec-default-deny-v2",
        "sandbox_executable" => @sandbox_executable,
        "sandbox_executable_sha256" => Digest::SHA256.file(@sandbox_executable).hexdigest,
        "read_roots" => (@read_roots + SYSTEM_READ_ROOTS.select { |path| File.exist?(path) }).uniq.sort,
        "environment_allowlist" => @environment_allowlist.sort,
        "network" => "deny",
        "iokit" => { "open_user_client_classes" => ["RootDomainUserClient"] },
        "mach_lookup" => { "global_name_prefixes" => ["org.chromium.Chromium.MachPortRendezvousServer."] },
        "mach_register" => { "global_name_prefixes" => ["org.chromium.Chromium.MachPortRendezvousServer."] },
        "write" => "disposable_run_root_only",
        "sensitive_existing_files" => "data_read_denied"
      }
      manifest["repository_view"] = @repository_view if @repository_view
      manifest
    end

    def check_plan_digest(plan)
      digest({ "check_plan" => plan, "execution_policy" => policy_manifest })
    end

    def git_changes(root = @project_root, executable = "/usr/bin/git")
      conflicts = git_output_at(root, executable, "diff", "--no-ext-diff", "--no-textconv", "--name-only", "--diff-filter=U", "-z", "HEAD", "--")
      fail!("candidate contains unresolved Git conflicts") unless conflicts.empty?
      tracked = parse_name_status(git_output_at(root, executable, "diff", "--no-ext-diff", "--no-textconv", "--name-status", "--no-renames", "-z", "HEAD", "--"), root)
      untracked = git_output_at(root, executable, "ls-files", "--others", "--exclude-standard", "-z", "--").split("\0").reject(&:empty?).map do |path|
        change_entry("?", path, root)
      end
      (tracked + untracked).sort_by { |entry| entry["path"] }
    end

    def parse_name_status(output, root = @project_root)
      fields = output.split("\0")
      entries = []
      index = 0
      while index < fields.length && !fields[index].empty?
        status = fields[index]
        path = fields[index + 1]
        fail!("Git returned an incomplete candidate record") unless status && path
        entries << change_entry(status, path, root)
        index += 2
      end
      entries
    end

    def change_entry(status, path, root = @project_root)
      relative = safe_relative_path!(path)
      fail!("unsupported Git candidate status #{status.inspect}") unless status.match?(/\A[AMDT?]\z/)
      entry = { "status" => status, "path" => relative }
      return entry.merge("sha256" => nil, "bytes" => nil) if status == "D"

      full = File.join(root, relative)
      safe_regular_file!(full, "candidate path")
      entry.merge("sha256" => Digest::SHA256.file(full).hexdigest, "bytes" => File.size(full))
    end

    def validate_change_scope!(changes, allowed_paths)
      allowed = allowed_paths.map { |path| safe_relative_path!(path) }
      changes.each do |entry|
        fail!("candidate path #{entry['path'].inspect} is outside authorized milestone reach") unless allowed.any? { |declaration| path_matches?(entry["path"], declaration) }
      end
    end

    def path_matches?(path, declaration)
      if declaration.include?("*") || declaration.include?("?") || declaration.include?("[")
        File.fnmatch?(declaration, path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
      else
        path == declaration
      end
    end

    def verify_candidate_manifest!(manifest, exact:)
      fail!("candidate schema is unsupported") unless manifest["schema_version"] == CANDIDATE_SCHEMA
      fail!("candidate project root changed") unless manifest["project_root"] == @project_root
      candidate_digest = manifest["candidate_digest"]
      fail!("candidate manifest digest mismatch") unless secure_equal?(candidate_digest, digest(manifest.reject { |key, _| key == "candidate_digest" }))
      fail!("candidate HEAD changed") unless manifest["head_sha"] == git_output("rev-parse", "HEAD").strip
      fail!("candidate HEAD tree changed") unless manifest["head_tree"] == git_output("rev-parse", "HEAD^{tree}").strip
      expected_executables = executable_identities(manifest.fetch("check_plan"))
      fail!("candidate check executable identity drifted") unless manifest["executable_identities"] == expected_executables
      current = git_changes
      expected = manifest.fetch("changes")
      if exact
        fail!("candidate Git changes drifted") unless current == expected
      else
        current_by_path = current.each_with_object({}) { |entry, memo| memo[entry["path"]] = entry }
        expected.each do |entry|
          fail!("candidate artifact drifted: #{entry['path']}") unless current_by_path[entry["path"]] == entry
        end
      end
      true
    end

    def sandbox_profile(run_root, project_root: @project_root)
      repository_executable = @repository_view && @repository_view["git_executable"]
      read_roots = [project_root, run_root, *@read_roots, repository_executable,
                    *SYSTEM_READ_ROOTS.select { |path| File.exist?(path) }].compact.uniq
      rules = ["(version 1)", "(deny default)", "(allow process*)", "(deny network*)", "(allow sysctl-read)"]
      rules << '(allow iokit-open (iokit-user-client-class "RootDomainUserClient"))'
      rules << '(allow mach-register (global-name-prefix "org.chromium.Chromium.MachPortRendezvousServer."))'
      rules << '(allow mach-lookup (global-name-prefix "org.chromium.Chromium.MachPortRendezvousServer."))'
      # Current macOS launchers inspect the root directory before resolving an
      # absolute executable. This literal grants only that directory entry; it
      # does not grant descendant reads as `(subpath \"/\")` would.
      rules << "(allow file-read* (literal \"/\"))"
      ancestor_directories(read_roots).each do |path|
        rules << "(allow file-read* (literal #{profile_string(path)}))"
      end
      read_roots.each { |path| rules << "(allow file-read* (subpath #{profile_string(path)}))" }
      discover_sensitive_existing_files(project_root).each do |path|
        rules << "(deny file-read-data (literal #{profile_string(path)}))"
      end
      rules << "(allow file-write* (subpath #{profile_string(run_root)}) (literal \"/dev/null\"))"
      if @repository_view && project_root != @project_root
        rules << "(deny file-write* (subpath #{profile_string(project_root)}))"
        %w[receipt.json stdout.bin stderr.bin].each do |name|
          rules << "(deny file-write* (literal #{profile_string(File.join(run_root, name))}))"
        end
      end
      rules.join(" ")
    end

    def ancestor_directories(paths)
      paths.each_with_object([]) do |path, result|
        current = File.dirname(path)
        until current == File::SEPARATOR || current == "."
          result << current
          parent = File.dirname(current)
          break if parent == current
          current = parent
        end
      end.uniq.sort
    end

    def preflight_isolation!(profile, run_root, project_root: @project_root)
      fail!("forbidden read sentinel is required") unless @forbidden_read_path
      fail!("forbidden write sentinel is required") unless @forbidden_write_path
      if readable_root?(@forbidden_read_path, run_root, project_root: project_root)
        fail!("forbidden read sentinel is accidentally readable by policy")
      end
      fail!("forbidden write sentinel is inside the disposable run root") if within?(@forbidden_write_path, run_root)

      read_result = execute_raw(["/bin/cat", @forbidden_read_path], {}, project_root, 10, 4096, profile)
      if read_result["exit_status"].zero? || read_result["timed_out"]
        fail!("sandbox preflight did not block forbidden read")
      end
      before = [Digest::SHA256.file(@forbidden_write_path).hexdigest, File.stat(@forbidden_write_path).mtime]
      write_result = execute_raw(["/usr/bin/touch", @forbidden_write_path], {}, project_root, 10, 4096, profile)
      after = [Digest::SHA256.file(@forbidden_write_path).hexdigest, File.stat(@forbidden_write_path).mtime]
      if write_result["exit_status"].zero? || before != after || write_result["timed_out"]
        fail!("sandbox preflight did not block forbidden write")
      end
      network_probe = <<~'RUBY'
        require "socket"
        begin
          socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
          socket.connect(Socket.sockaddr_in(9, "127.0.0.1"))
          socket.close
          exit 9
        rescue Errno::EPERM, Errno::EACCES
          exit 0
        rescue SystemCallError
          exit 8
        end
      RUBY
      network_result = execute_raw([File.realpath(RbConfig.ruby), "-e", network_probe], {}, project_root, 10, 4096, profile)
      if !network_result["exit_status"].zero? || network_result["timed_out"]
        fail!("sandbox preflight did not block network")
      end
      { "forbidden_read" => "blocked", "forbidden_write" => "blocked", "network" => "blocked" }
    end

    def declared_environment(spec)
      canonical_value(spec)
    end

    def executable_identity(path)
      path = canonical_executable!(path, "argv executable")
      stat = File.stat(path)
      { "path" => path, "sha256" => Digest::SHA256.file(path).hexdigest, "bytes" => stat.size, "mode" => stat.mode & 0o777 }
    end

    def preflight_conclusion(result, startup_completed: nil)
      return "output_limit_exceeded" if result["output_limit_exceeded"]
      return "timed_out" if result["timed_out"]
      return "startup_failed" if result["term_signal"]
      return "startup_failed" if startup_completed == false
      result["exit_status"].zero? ? "passed" : "failed"
    end

    def execute_process(spec, profile, run_root)
      environment = spec.fetch("env").merge("TMPDIR" => run_root)
      execute_raw(
        spec.fetch("argv"), environment, spec.fetch("cwd"), spec.fetch("timeout_seconds"),
        spec.fetch("max_output_bytes", MAX_OUTPUT_BYTES), profile
      )
    end

    def materialize_spec(spec, run_root, candidate_root = @project_root)
      materialized = canonical_value(spec)
      materialized["argv"] = materialized.fetch("argv").map do |value|
        value.gsub(RUN_ROOT_TOKEN, run_root).gsub(CANDIDATE_ROOT_TOKEN, candidate_root)
      end
      materialized["env"] = materialized.fetch("env").each_with_object({}) do |(name, value), memo|
        memo[name] = value.gsub(RUN_ROOT_TOKEN, run_root).gsub(CANDIDATE_ROOT_TOKEN, candidate_root)
      end
      materialized["configuration_paths"] = materialized.fetch("configuration_paths").map do |value|
        value.gsub(RUN_ROOT_TOKEN, run_root)
      end
      source_cwd = canonical_directory!(materialized.fetch("cwd"), "execution cwd")
      relative_cwd = Pathname.new(source_cwd).relative_path_from(Pathname.new(@project_root)).to_s
      materialized["cwd"] = relative_cwd == "." ? candidate_root : File.join(candidate_root, relative_cwd)
      materialized
    end

    def execution_id(spec, binding, candidate)
      digest({
        "candidate_digest" => candidate.fetch("candidate_digest"),
        "check_plan_digest" => binding.fetch("check_plan_digest"),
        "check_id" => spec.fetch("id"),
        "environment_id" => spec.fetch("environment_id")
      })
    end

    def executable_identities(plan)
      Array(plan["checks"]).each_with_object({}) do |spec, identities|
        path = canonical_executable!(spec.fetch("argv").first, "argv executable")
        stat = File.stat(path)
        identities[spec.fetch("id")] = {
          "path" => path,
          "sha256" => Digest::SHA256.file(path).hexdigest,
          "bytes" => stat.size,
          "mode" => stat.mode & 0o777
        }
      end
    end

    def validate_repository_view!(value)
      return nil if value.nil?
      view = stringify_hash!(canonical_value(value), "repository view")
      expected_keys!(view, %w[schema_version kind git_executable])
      fail!("repository view schema is unsupported") unless view["schema_version"] == REPOSITORY_VIEW_SCHEMA
      fail!("repository view kind is unsupported") unless view["kind"] == "isolated_head_candidate"
      view["git_executable"] = canonical_executable!(view.fetch("git_executable"), "repository view Git executable")
      view.freeze
    end

    def repository_environment
      git_directory = File.dirname(@repository_view.fetch("git_executable"))
      {
        "PATH" => "#{git_directory}:/usr/bin:/bin",
        "GIT_CONFIG_NOSYSTEM" => "1",
        "GIT_CONFIG_GLOBAL" => "/dev/null",
        "GIT_CONFIG_SYSTEM" => "/dev/null",
        "GIT_ATTR_NOSYSTEM" => "1",
        "GIT_OPTIONAL_LOCKS" => "0",
        "GIT_NO_LAZY_FETCH" => "1",
        "GIT_TERMINAL_PROMPT" => "0"
      }
    end

    # Materialize only the exact candidate HEAD commit and the tree/blob closure
    # reachable from it. The commit's parent names remain in the commit bytes, but
    # their objects, refs, reflogs, remotes and configuration are not copied.
    def prepare_repository_view!(run_root, candidate)
      return nil unless @repository_view
      git = @repository_view.fetch("git_executable")
      root = File.join(run_root, "candidate")
      remove_repository_view!(root, run_root) if File.exist?(root) || File.symlink?(root)
      Dir.mkdir(root, 0o700)
      top = git_output_at(@project_root, git, "rev-parse", "--show-toplevel").strip
      fail!("repository view source is not the candidate Git top-level") unless File.realpath(top) == @project_root
      git_checked!(git, root, "init", "--quiet")
      FileUtils.rm_rf(File.join(root, ".git", "hooks"))
      FileUtils.rm_rf(File.join(root, ".git", "logs"))
      FileUtils.rm_rf(File.join(root, ".git", "objects", "info", "alternates"))
      File.open(File.join(root, ".git", "config"), "wb", 0o600) do |file|
        file.write("[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = false\n\tlogallrefupdates = false\n")
      end

      head = candidate.fetch("head_sha")
      tree = candidate.fetch("head_tree")
      ids = git_output_at(@project_root, git, "rev-list", "--objects", "--no-object-names", "#{tree}^{tree}")
            .lines.map(&:strip).reject(&:empty?).uniq
      fail!("repository view object set is empty") if ids.empty?
      ids.unshift(head)
      ids.uniq!
      fail!("repository view exceeds object count bound") if ids.length > MAX_REPOSITORY_OBJECTS
      total_bytes = 0
      ids.each do |oid|
        fail!("repository view contains an invalid object id") unless oid.match?(/\A[0-9a-f]{40}\z/)
        type = git_output_at(@project_root, git, "cat-file", "-t", oid).strip
        fail!("repository view contains an unsupported object type") unless %w[blob tree commit].include?(type)
        size = Integer(git_output_at(@project_root, git, "cat-file", "-s", oid).strip, 10)
        total_bytes += size
        fail!("repository view exceeds object byte bound") if total_bytes > MAX_REPOSITORY_OBJECT_BYTES
        bytes = git_output_at(@project_root, git, "cat-file", type, oid, binary: true)
        fail!("repository object size changed while copying") unless bytes.bytesize == size
        copied = git_output_at(root, git, "hash-object", "--no-filters", "-w", "-t", type, "--stdin", stdin_data: bytes).strip
        fail!("repository object identity changed while copying") unless copied == oid
      end

      git_checked!(git, root, "symbolic-ref", "HEAD", "refs/heads/candidate")
      git_checked!(git, root, "update-ref", "refs/heads/candidate", head)
      git_checked!(git, root, "read-tree", "HEAD")
      materialize_head_tree!(root, git, head)
      overlay_candidate!(root, git, candidate.fetch("changes"))
      isolated_changes = git_changes(root, git)
      fail!("isolated repository candidate differs from the captured candidate") unless isolated_changes == candidate.fetch("changes")
      parent_available = git_status_at(root, git, "cat-file", "-e", "#{head}^")
      fail!("repository view unexpectedly contains parent history") if parent_available.success?
      protect_repository_metadata!(root)
      metadata = repository_metadata_snapshot(root)

      relative = Pathname.new(root).relative_path_from(Pathname.new(@state_dir)).to_s
      receipt = {
        "schema_version" => REPOSITORY_VIEW_SCHEMA,
        "kind" => "isolated_head_candidate",
        "source_project_root" => @project_root,
        "validation_root" => relative,
        "head_sha" => head,
        "head_tree" => tree,
        "candidate_digest" => candidate.fetch("candidate_digest"),
        "candidate_changes_sha256" => digest(candidate.fetch("changes")),
        "object_count" => ids.length,
        "object_bytes" => total_bytes,
        "object_ids_sha256" => Digest::SHA256.hexdigest(ids.sort.join("\n") << "\n"),
        "metadata_entries" => metadata.fetch("entries"),
        "metadata_sha256" => metadata.fetch("sha256"),
        "parent_objects" => "omitted",
        "git_executable" => executable_identity(git)
      }
      { "root" => root, "receipt" => receipt }
    rescue ArgumentError
      fail!("repository view contains an invalid object size")
    end

    def materialize_head_tree!(root, git, head)
      output = git_output_at(root, git, "ls-tree", "-r", "-z", head, binary: true)
      output.split("\0").reject(&:empty?).each do |record|
        metadata, relative = record.split("\t", 2)
        mode, type, oid = metadata.to_s.split(" ", 3)
        path = safe_relative_path!(relative)
        unless type == "blob" && %w[100644 100755].include?(mode)
          fail!("repository view supports only regular tracked files")
        end
        destination = File.join(root, path)
        FileUtils.mkdir_p(File.dirname(destination), mode: 0o700)
        bytes = git_output_at(root, git, "cat-file", "blob", oid, binary: true)
        File.open(destination, File::WRONLY | File::CREAT | File::EXCL, mode == "100755" ? 0o700 : 0o600) do |file|
          file.binmode
          file.write(bytes)
        end
      end
    end

    def overlay_candidate!(root, git, changes)
      changes.each do |entry|
        relative = safe_relative_path!(entry.fetch("path"))
        destination = File.join(root, relative)
        if entry.fetch("status") == "D"
          FileUtils.rm_f(destination)
          next
        end
        source = File.join(@project_root, relative)
        safe_regular_file!(source, "candidate overlay path")
        FileUtils.mkdir_p(File.dirname(destination), mode: 0o700)
        FileUtils.copy_file(source, destination)
        File.chmod(File.stat(source).mode & 0o111 == 0 ? 0o600 : 0o700, destination)
        next unless entry.fetch("status") == "A"

        empty = git_output_at(root, git, "hash-object", "--no-filters", "-w", "--stdin", stdin_data: "").strip
        mode = File.stat(source).mode & 0o111 == 0 ? "100644" : "100755"
        git_checked!(git, root, "update-index", "--add", "--cacheinfo", "#{mode},#{empty},#{relative}")
      end
    end

    def verify_repository_view_receipt!(view, candidate)
      if @repository_view.nil?
        fail!("native receipt unexpectedly uses a repository view") if view
        return true
      end
      verify_repository_view!(view, candidate)
    end

    def verify_repository_view!(view, candidate)
      fail!("native receipt repository view is missing") unless view.is_a?(Hash)
      expected = %w[candidate_changes_sha256 candidate_digest git_executable head_sha head_tree kind metadata_entries metadata_sha256 object_bytes object_count object_ids_sha256 parent_objects schema_version source_project_root validation_root]
      fail!("native receipt repository view is malformed") unless view.keys.sort == expected.sort
      fail!("native receipt repository view schema changed") unless view["schema_version"] == REPOSITORY_VIEW_SCHEMA && view["kind"] == "isolated_head_candidate"
      fail!("native receipt repository source changed") unless view["source_project_root"] == @project_root
      fail!("native receipt repository candidate changed") unless view["candidate_digest"] == candidate["candidate_digest"] &&
        view["candidate_changes_sha256"] == digest(candidate.fetch("changes")) && view["head_sha"] == candidate["head_sha"] &&
        view["head_tree"] == candidate["head_tree"]
      fail!("native receipt repository history policy changed") unless view["parent_objects"] == "omitted"
      fail!("native receipt repository Git identity changed") unless view["git_executable"] == executable_identity(@repository_view.fetch("git_executable"))
      root = safe_state_directory!(view.fetch("validation_root"))
      fail!("native receipt repository root name changed") unless File.basename(root) == "candidate"
      metadata = repository_metadata_snapshot(root)
      unless metadata["entries"] == view["metadata_entries"] && metadata["sha256"] == view["metadata_sha256"]
        fail!("native receipt repository metadata changed")
      end
      git = @repository_view.fetch("git_executable")
      fail!("native receipt repository HEAD changed") unless git_output_at(root, git, "rev-parse", "HEAD").strip == candidate["head_sha"]
      fail!("native receipt repository tree changed") unless git_output_at(root, git, "rev-parse", "HEAD^{tree}").strip == candidate["head_tree"]
      fail!("native receipt repository candidate drifted") unless git_changes(root, git) == candidate.fetch("changes")
      fail!("native receipt repository unexpectedly gained parent history") if git_status_at(root, git, "cat-file", "-e", "#{candidate.fetch('head_sha')}^").success?
      true
    end

    def protect_repository_metadata!(root)
      metadata_root = File.join(root, ".git")
      paths = Dir.glob(File.join(metadata_root, "**", "*"), File::FNM_DOTMATCH).reject do |path|
        %w[. ..].include?(File.basename(path))
      end.sort_by { |path| -path.count(File::SEPARATOR) }
      paths.each do |path|
        stat = File.lstat(path)
        fail!("repository metadata may not contain symlinks or special files") unless stat.file? || stat.directory?
        File.chmod(stat.directory? ? 0o500 : 0o400, path)
      end
      File.chmod(0o500, metadata_root)
    end

    def remove_repository_view!(root, run_root)
      fail!("repository view cleanup escaped its run root") unless within?(root, run_root)
      fail!("repository view cleanup refuses a symlink") if File.symlink?(root)
      paths = Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).reject do |path|
        %w[. ..].include?(File.basename(path))
      end.sort_by { |path| -path.count(File::SEPARATOR) }
      paths.each do |path|
        stat = File.lstat(path)
        fail!("repository view cleanup found a symlink or special file") unless stat.file? || stat.directory?
        File.chmod(stat.directory? ? 0o700 : 0o600, path)
      end
      File.chmod(0o700, root)
      FileUtils.remove_entry(root)
    end

    def privatize_run_scratch!(run_root, except: nil)
      paths = Dir.glob(File.join(run_root, "**", "*"), File::FNM_DOTMATCH).reject do |path|
        %w[. ..].include?(File.basename(path)) || (except && within?(path, except))
      end.sort_by { |path| -path.count(File::SEPARATOR) }
      paths.each do |path|
        stat = File.lstat(path)
        fail!("execution scratch contains a symlink or special file") unless stat.file? || stat.directory?
        fail!("execution scratch has an unsafe owner") unless stat.uid == Process.uid
        File.chmod(stat.directory? ? 0o700 : (stat.mode & 0o111 == 0 ? 0o600 : 0o700), path)
      end
    end

    def repository_metadata_snapshot(root)
      metadata_root = File.join(root, ".git")
      fail!("repository metadata root is unsafe") unless File.directory?(metadata_root) && !File.symlink?(metadata_root)
      entries = Dir.glob(File.join(metadata_root, "**", "*"), File::FNM_DOTMATCH).reject do |path|
        %w[. ..].include?(File.basename(path))
      end.sort.map do |path|
        relative = Pathname.new(path).relative_path_from(Pathname.new(metadata_root)).to_s
        forbidden = %w[commondir config.worktree shallow info/grafts objects/info/alternates objects/info/http-alternates]
        if forbidden.include?(relative) || relative.start_with?("refs/replace/")
          fail!("repository metadata contains a forbidden control entry")
        end
        stat = File.lstat(path)
        if stat.directory?
          { "path" => relative, "type" => "directory", "mode" => stat.mode & 0o777,
            "uid" => stat.uid, "nlink" => stat.nlink }
        elsif stat.file?
          fail!("repository metadata contains a hard-linked file") unless stat.nlink == 1
          { "path" => relative, "type" => "file", "mode" => stat.mode & 0o777,
            "uid" => stat.uid, "nlink" => stat.nlink, "bytes" => stat.size,
            "sha256" => Digest::SHA256.file(path).hexdigest }
        else
          fail!("repository metadata may not contain symlinks or special files")
        end
      end
      fail!("repository metadata exceeds entry bound") if entries.length > MAX_REPOSITORY_OBJECTS * 3
      { "entries" => entries.length, "sha256" => digest(entries) }
    end

    def discover_sensitive_existing_files(root = @project_root)
      # Dependency roots are selected by the host plan and may legitimately
      # contain packaged key/database fixtures. Existing project-local runtime
      # data is the user-data risk this deny list isolates.
      [root].each_with_object([]) do |candidate_root, paths|
        next if File.file?(candidate_root)
        Dir.glob(File.join(candidate_root, "**", "*"), File::FNM_DOTMATCH).each do |path|
          basename = File.basename(path)
          next unless basename.match?(SENSITIVE_BASENAME)
          begin
            stat = File.lstat(path)
            paths << File.realpath(path) if stat.file? && !stat.symlink?
          rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP
            next
          end
        end
      end.uniq.sort
    end

    def execute_raw(argv, environment, cwd, timeout_seconds, max_output_bytes, profile)
      command = [@sandbox_executable, "-p", profile, *argv]
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout_text = nil
      stderr_text = nil
      status = nil
      timed_out = false
      output_limit_exceeded = false
      output_bytes = 0
      mutex = Mutex.new
      Open3.popen3(environment, *command, chdir: cwd, unsetenv_others: true, pgroup: true) do |stdin, stdout, stderr, wait_thread|
        stdin.close
        reader = lambda do |stream|
          stream.binmode
          chunks = []
          begin
            loop do
              chunk = stream.readpartial(READ_CHUNK_BYTES)
              chunks << chunk
              should_kill = mutex.synchronize do
                output_bytes += chunk.bytesize
                if output_bytes > max_output_bytes && !output_limit_exceeded
                  output_limit_exceeded = true
                  true
                else
                  false
                end
              end
              kill_process_group(wait_thread.pid, "KILL") if should_kill
            end
          rescue EOFError
            chunks.join
          end
        end
        stdout_reader = Thread.new { reader.call(stdout) }
        stderr_reader = Thread.new { reader.call(stderr) }
        begin
          Timeout.timeout(timeout_seconds) { status = wait_thread.value }
        rescue Timeout::Error
          timed_out = true
          kill_process_group(wait_thread.pid, "TERM")
          kill_process_group(wait_thread.pid, "KILL") unless wait_thread.join(0.25)
          status = wait_thread.value
        ensure
          kill_process_group(wait_thread.pid, "TERM")
          kill_process_group(wait_thread.pid, "KILL")
          stdout_text = stdout_reader.value
          stderr_text = stderr_reader.value
        end
      end
      {
        "stdout" => stdout_text,
        "stderr" => stderr_text,
        "exit_status" => status.exitstatus || 128 + status.termsig.to_i,
        "term_signal" => status.signaled? ? status.termsig : nil,
        "timed_out" => timed_out,
        "output_limit_exceeded" => output_limit_exceeded,
        "duration_milliseconds" => ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).ceil
      }
    rescue Errno::ENOENT, Errno::EACCES => e
      fail!("native execution failed to start: #{e.message}")
    end

    def kill_process_group(pid, signal)
      Process.kill(signal, -pid)
    rescue Errno::ESRCH
      nil
    end

    def receipt_authentication(unsigned)
      key = File.binread(@receipt_key_path)
      { "algorithm" => "hmac-sha256", "hmac_sha256" => OpenSSL::HMAC.hexdigest("SHA256", key, canonical_json(unsigned)) }
    end

    def receipt_descriptor(path)
      relative = Pathname.new(path).relative_path_from(Pathname.new(@state_dir)).to_s
      { "receipt_path" => relative, "receipt_sha256" => Digest::SHA256.file(path).hexdigest }
    end

    def private_log_descriptor(path)
      {
        "path" => Pathname.new(path).relative_path_from(Pathname.new(@state_dir)).to_s,
        "sha256" => Digest::SHA256.file(path).hexdigest,
        "bytes" => File.size(path)
      }
    end

    def verify_private_log!(descriptor)
      descriptor = stringify_hash!(descriptor, "private log descriptor")
      expected_keys!(descriptor, %w[path sha256 bytes])
      path = safe_state_file!(descriptor.fetch("path"))
      fail!("private log byte count changed") unless File.size(path) == descriptor.fetch("bytes")
      read_private_file!(path, descriptor.fetch("sha256"))
    end

    def write_private_exclusive!(directory, basename, contents)
      path = File.join(directory, basename)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL | nofollow_flag, 0o600) do |file|
        file.binmode
        file.write(contents)
        file.flush
        file.fsync
      end
      File.chmod(0o600, path)
      path
    rescue Errno::EEXIST, Errno::ELOOP => e
      fail!("runner output path is not fresh: #{e.message}")
    end

    def read_private_file!(path, expected_sha256)
      safe_regular_file!(path, "private execution file", private: true)
      contents = File.open(path, File::RDONLY | nofollow_flag) do |file|
        file.binmode
        file.read
      end
      fail!("private execution file digest mismatch") unless secure_equal?(Digest::SHA256.hexdigest(contents), expected_sha256)
      contents
    end

    def safe_state_file!(relative)
      relative = safe_relative_path!(relative)
      path = File.expand_path(File.join(@state_dir, relative))
      fail!("execution receipt path escapes state_dir") unless within?(path, @state_dir)
      each_component_no_symlink!(@state_dir, relative)
      path
    end

    def canonical_directory!(path, label)
      fail!("#{label} must be an absolute path") unless path.is_a?(String) && Pathname.new(path).absolute?
      fail!("#{label} must be a directory") unless File.directory?(path)
      canonical = File.realpath(path)
      fail!("#{label} must be canonical") unless path == canonical
      fail!("#{label} must not be a symlink") if File.lstat(path).symlink?
      canonical
    rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR => e
      fail!("#{label} cannot be accessed: #{e.message}")
    end

    def canonical_private_directory!(path)
      canonical = canonical_directory!(path, "state_dir")
      stat = File.lstat(canonical)
      fail!("state_dir must use owner-only mode 0700") unless stat.uid == Process.uid && (stat.mode & 0o777) == 0o700
      canonical
    end

    def canonical_read_root!(path)
      fail!("read roots must be absolute") unless path.is_a?(String) && Pathname.new(path).absolute?
      fail!("read root must not be filesystem root") if File.expand_path(path) == File::SEPARATOR
      fail!("read root must not be a symlink") if File.lstat(path).symlink?
      File.realpath(path)
    rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR => e
      fail!("read root cannot be accessed: #{e.message}")
    end

    def canonical_executable!(path, label)
      fail!("#{label} must be an absolute path") unless path.is_a?(String) && Pathname.new(path).absolute?
      fail!("#{label} must not be a symlink") if File.lstat(path).symlink?
      canonical = File.realpath(path)
      fail!("#{label} must be a regular executable") unless File.file?(canonical) && File.executable?(canonical)
      canonical
    rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => e
      fail!("#{label} cannot be accessed: #{e.message}")
    end

    def optional_canonical_file(path, label)
      return nil if path.nil?
      fail!("#{label} must be an absolute regular file") unless path.is_a?(String) && Pathname.new(path).absolute?
      fail!("#{label} must not be a symlink") if File.lstat(path).symlink?
      canonical = File.realpath(path)
      fail!("#{label} must be a regular file") unless File.file?(canonical)
      canonical
    rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => e
      fail!("#{label} cannot be accessed: #{e.message}")
    end

    def safe_regular_file!(path, label, private: false)
      stat = File.lstat(path)
      fail!("#{label} must not be a symlink") if stat.symlink?
      fail!("#{label} must be a regular file") unless stat.file?
      if private && (stat.uid != Process.uid || (stat.mode & 0o777) != 0o600)
        fail!("#{label} must use owner-only mode 0600")
      end
      true
    rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => e
      fail!("#{label} cannot be accessed: #{e.message}")
    end

    def safe_relative_path!(path)
      fail!("path must be a relative string") unless path.is_a?(String) && !path.empty? && !path.include?("\0")
      pathname = Pathname.new(path)
      clean = pathname.cleanpath.to_s
      fail!("path escapes its root: #{path.inspect}") if pathname.absolute? || clean == "." || clean == ".." || clean.start_with?("../") || clean != path
      clean
    end

    def each_component_no_symlink!(root, relative)
      current = root
      relative.split(File::SEPARATOR).each do |component|
        current = File.join(current, component)
        fail!("symlink path components are forbidden") if File.lstat(current).symlink?
      end
    rescue Errno::ENOENT, Errno::EACCES => e
      fail!("path cannot be accessed: #{e.message}")
    end

    def readable_root?(path, run_root, project_root: @project_root)
      repository_executable = @repository_view && @repository_view["git_executable"]
      [project_root, run_root, *@read_roots, repository_executable,
       *SYSTEM_READ_ROOTS.select { |root| File.exist?(root) }].compact.any? { |root| within?(path, File.realpath(root)) }
    end

    def within?(path, root)
      path == root || path.start_with?(root.end_with?(File::SEPARATOR) ? root : "#{root}#{File::SEPARATOR}")
    end

    def profile_string(value)
      JSON.generate(value)
    end

    def git_output(*arguments)
      git_output_at(@project_root, "/usr/bin/git", *arguments)
    end

    def git_output_at(root, executable, *arguments, binary: false, stdin_data: nil)
      environment = trusted_git_environment(root)
      options = { unsetenv_others: true }
      options[:stdin_data] = stdin_data unless stdin_data.nil?
      output, error, status = Open3.capture3(environment, executable, *trusted_git_arguments(root, arguments), **options)
      fail!("Git candidate inspection failed: #{error.strip}") unless status.success?
      output.force_encoding(Encoding::BINARY) if binary
      output
    end

    def git_checked!(executable, root, *arguments)
      git_output_at(root, executable, *arguments)
      true
    end

    def git_status_at(root, executable, *arguments)
      _output, _error, status = Open3.capture3(
        trusted_git_environment(root), executable, *trusted_git_arguments(root, arguments), unsetenv_others: true
      )
      status
    end

    def trusted_git_environment(root)
      {
        "LC_ALL" => "C", "GIT_CONFIG_NOSYSTEM" => "1", "GIT_CONFIG_GLOBAL" => "/dev/null",
        "GIT_CONFIG_SYSTEM" => "/dev/null", "GIT_ATTR_NOSYSTEM" => "1", "GIT_OPTIONAL_LOCKS" => "0",
        "GIT_NO_LAZY_FETCH" => "1", "GIT_TERMINAL_PROMPT" => "0", "HOME" => File.dirname(root)
      }
    end

    def trusted_git_arguments(root, arguments)
      global = ["--no-pager", "--no-replace-objects", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"]
      if File.directory?(File.join(root, ".git"))
        global + ["--git-dir=#{File.join(root, '.git')}", "--work-tree=#{root}", *arguments]
      else
        global + ["-C", root, *arguments]
      end
    end

    def safe_state_directory!(relative)
      relative = safe_relative_path!(relative)
      path = File.expand_path(File.join(@state_dir, relative))
      fail!("repository view path escapes state_dir") unless within?(path, @state_dir)
      each_component_no_symlink!(@state_dir, relative)
      fail!("repository view path is not a directory") unless File.directory?(path)
      path
    end

    def canonical_value(value)
      self.class.canonical(value)
    end

    def canonical_json(value)
      JSON.generate(canonical_value(value))
    end

    def digest(value)
      Digest::SHA256.hexdigest(value.is_a?(String) ? value : canonical_json(value))
    end

    def stringify_hash!(value, label)
      fail!("#{label} must be a JSON object") unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
      value
    end

    def expected_keys!(value, required, optional = [])
      missing = required - value.keys
      extra = value.keys - required - optional
      fail!("missing keys: #{missing.join(', ')}") unless missing.empty?
      fail!("unknown keys: #{extra.join(', ')}") unless extra.empty?
    end

    def secure_equal?(actual, expected)
      return false unless actual.is_a?(String) && expected.is_a?(String) && actual.bytesize == expected.bytesize
      difference = 0
      actual.bytes.zip(expected.bytes) { |left, right| difference |= left ^ right }
      difference.zero?
    end

    def nofollow_flag
      defined?(File::NOFOLLOW) ? File::NOFOLLOW : 0
    end

    def fail!(message)
      raise HrmKernel::Error.new("invalid_execution", message)
    end
  end
end
