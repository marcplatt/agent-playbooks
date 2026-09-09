#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"

require_relative "../lib/hrm_kernel/store"

module HrmKernel
  module CLI
    ROLES = %w[orchestrator worker operator reviewer].freeze
    MAX_INPUT_BYTES = 4 * 1024 * 1024

    module_function

    def run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      command = argv.shift
      return print_help(stdout, 0) if command.nil? || command == "--help" || command == "-h"

      output = case command
               when "apply" then apply(argv, stdin)
               when "status" then status(argv)
               when "verify" then verify(argv)
               when "host-dispatch", "host-status", "host-collect" then host(command, argv, stdin)
               when "check", "submit", "assess" then coordinate(command, argv, stdin)
               when "driver-start", "driver-step", "driver-status", "driver-run", "driver-input" then drive(command, argv, stdin)
               when "driver-continue" then continue_run(argv, stdin)
               else
                 raise HrmKernel::Error, "unknown command #{command.inspect}"
               end
      stdout.puts(JSON.generate(output))
      0
    rescue HrmKernel::Error, OptionParser::ParseError, JSON::ParserError, SystemCallError, KeyError, ArgumentError => e
      failure = { "error" => e.message }
      failure["code"] = if e.is_a?(HrmKernel::Error)
                          e.code
                        elsif e.is_a?(SystemCallError)
                          "io_error"
                        else
                          "invalid_input"
                        end
      failure["details"] = e.details if e.is_a?(HrmKernel::Error) && e.details
      stderr.puts(JSON.generate(failure))
      1
    end

    def apply(argv, stdin)
      options = parse_options(argv, input: true)
      parsed = input_object(options, stdin)
      Store.new(options.fetch(:state_dir)).transact(parsed)
    end

    def input_object(options, stdin)
      input = options.fetch(:input)
      json = if input == "-"
               read_bounded(stdin, "standard input")
             else
               File.open(input, "r:UTF-8") { |file| read_bounded(file, input) }
             end
      parsed = JSON.parse(json)
      raise HrmKernel::Error, "input must be a JSON object" unless parsed.is_a?(Hash)

      parsed
    end

    def host(command, argv, stdin)
      require_relative "../lib/hrm_kernel/host"
      options = parse_options(argv, input: true)
      input = input_object(options, stdin)
      adapter = Host.new(state_dir: options.fetch(:state_dir))
      case command
      when "host-dispatch" then adapter.dispatch(input)
      when "host-status" then adapter.poll(job_id: input.fetch("job_id"))
      when "host-collect" then adapter.collect(job_id: input.fetch("job_id"))
      end
    end

    def drive(command, argv, stdin)
      require_relative "../lib/hrm_kernel/driver"
      options = parse_options(argv, input: %w[driver-start driver-input].include?(command))
      driver = Driver.new(state_dir: options.fetch(:state_dir))
      case command
      when "driver-start" then driver.start(input_object(options, stdin))
      when "driver-input" then driver.technical_input(input_object(options, stdin))
      when "driver-status" then driver.status
      when "driver-step" then driver.step
      when "driver-run"
        loop do
          result = driver.step
          return result if Driver::TERMINAL.include?(result["outcome"])
          sleep 2
        end
      end
    end

    def coordinate(command, argv, stdin)
      require_relative "../lib/hrm_kernel/coordinator"
      options = parse_options(argv, input: true)
      input = input_object(options, stdin)
      coordinator = Coordinator.new(state_dir: options.fetch(:state_dir))
      case command
      when "check" then coordinator.check(input)
      when "submit" then coordinator.submit(input)
      when "assess" then coordinator.assess(input)
      end
    end

    def continue_run(argv, stdin)
      require_relative "../lib/hrm_kernel/run_continuation"
      options = parse_continuation_options(argv)
      input = input_object(options, stdin)
      allowed = %w[new_run_id source_kernel_root source_kernel_revision controller_stopped supervisor_provenance production]
      raise HrmKernel::Error, "unknown driver continuation fields" unless (input.keys - allowed).empty?
      HrmKernel::RunContinuation.clone(
        source_state_dir: options.fetch(:state_dir),
        destination_state_dir: options.fetch(:destination_state_dir),
        new_run_id: input.fetch("new_run_id"),
        source_kernel_root: input.fetch("source_kernel_root"),
        source_kernel_revision: input.fetch("source_kernel_revision"),
        controller_stopped: input.fetch("controller_stopped"),
        supervisor_provenance: input.fetch("supervisor_provenance"),
        production: input.fetch("production", true)
      )
    end

    def status(argv)
      options = parse_options(argv, role: true)
      Store.new(options.fetch(:state_dir)).project(
        role: options.fetch(:role),
        actor_id: options[:actor_id]
      )
    end

    def verify(argv)
      options = parse_options(argv)
      Store.new(options.fetch(:state_dir)).verify!
    end

    def parse_options(argv, input: false, role: false)
      options = {}
      parser = OptionParser.new do |opts|
        opts.on("--state-dir DIR") { |value| options[:state_dir] = value }
        opts.on("--input FILE") { |value| options[:input] = value } if input
        if role
          opts.on("--role ROLE") { |value| options[:role] = value }
          opts.on("--actor-id ID") { |value| options[:actor_id] = value }
        end
        opts.on("-h", "--help") do
          raise HrmKernel::Error, "use top-level --help for usage"
        end
      end
      parser.parse!(argv)
      raise OptionParser::ParseError, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
      raise OptionParser::MissingArgument, "--state-dir" unless options[:state_dir]
      raise OptionParser::MissingArgument, "--input" if input && !options[:input]
      if role
        raise OptionParser::MissingArgument, "--role" unless options[:role]
        unless ROLES.include?(options[:role])
          raise OptionParser::InvalidArgument, "--role must be one of #{ROLES.join(', ')}"
        end
      end
      options
    end

    def parse_continuation_options(argv)
      options = {}
      parser = OptionParser.new do |opts|
        opts.on("--state-dir DIR") { |value| options[:state_dir] = value }
        opts.on("--destination-state-dir DIR") { |value| options[:destination_state_dir] = value }
        opts.on("--input FILE") { |value| options[:input] = value }
      end
      parser.parse!(argv)
      raise OptionParser::ParseError, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
      raise OptionParser::MissingArgument, "--state-dir" unless options[:state_dir]
      raise OptionParser::MissingArgument, "--destination-state-dir" unless options[:destination_state_dir]
      raise OptionParser::MissingArgument, "--input" unless options[:input]
      options
    end

    def read_bounded(input, label)
      contents = input.read(MAX_INPUT_BYTES + 1)
      raise HrmKernel::Error, "#{label} exceeds #{MAX_INPUT_BYTES} bytes" if contents.bytesize > MAX_INPUT_BYTES

      contents
    end

    def print_help(output, status)
      output.puts <<~HELP
        Usage:
          ruby scripts/hrm_kernel.rb apply --state-dir DIR --input JSONFILE
          ruby scripts/hrm_kernel.rb apply --state-dir DIR --input -
          ruby scripts/hrm_kernel.rb status --state-dir DIR --role orchestrator|worker|operator|reviewer [--actor-id ID]
          ruby scripts/hrm_kernel.rb verify --state-dir DIR

          ruby scripts/hrm_kernel.rb host-dispatch --state-dir DIR --input JOB.json
          ruby scripts/hrm_kernel.rb host-status --state-dir DIR --input JOB_ID.json
          ruby scripts/hrm_kernel.rb host-collect --state-dir DIR --input JOB_ID.json
          ruby scripts/hrm_kernel.rb check --state-dir DIR --input CHECK_ID.json
          ruby scripts/hrm_kernel.rb submit --state-dir DIR --input JOB_ID.json
          ruby scripts/hrm_kernel.rb assess --state-dir DIR --input REVIEW_JOB_ID.json

          ruby scripts/hrm_kernel.rb driver-start --state-dir DIR --input DRIVER.json
          ruby scripts/hrm_kernel.rb driver-input --state-dir DIR --input TECHNICAL_INPUT.json
          ruby scripts/hrm_kernel.rb driver-continue --state-dir SOURCE_DIR --destination-state-dir DESTINATION_DIR --input CONTINUATION.json
          ruby scripts/hrm_kernel.rb driver-step --state-dir DIR
          ruby scripts/hrm_kernel.rb driver-status --state-dir DIR
          ruby scripts/hrm_kernel.rb driver-run --state-dir DIR

        RC36 adopts technical supervisor input explicitly through driver-input; existing RC35 state is not rewritten by inspection.
        Protocol ap-hrm-interaction/2 operator ledgers remain separate and are never upgraded in place.
        Native checks and Codex task identities are recorded by the local host adapter.
        Operator input remains a trusted local caller boundary; human acceptance is never inferred.
      HELP
      status
    end
  end
end

exit(HrmKernel::CLI.run(ARGV)) if $PROGRAM_NAME == __FILE__
